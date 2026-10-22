import Foundation
import UIKit

// MARK: - CactusManager
// Singleton that owns the on-device Gemma 4 model via Cactus framework.
// All three OnDevice providers share this single model handle.

final class CactusManager {

    // MARK: Shared
    static let shared = CactusManager()

    // MARK: - State
    enum ModelState {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: ModelState = .idle

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    // MARK: - Private
    private var modelHandle: CactusModelT?
    private let inferenceQueue = DispatchQueue(label: "Spendy.CactusManager.inference")
    // Cactus uses its own weight format (directory with config.txt + tokenizer files + *.weights).
    private let modelDirCandidates = [
        "gemma-4-e2b-m23k-cot-sft-lora-int4",
        "gemma-4-e2b-it"
    ]

    private func modelDestURL(for modelDirName: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(modelDirName)
    }

    private init() {}

    private struct SendableModelHandle: @unchecked Sendable {
        let rawValue: CactusModelT
    }

    // MARK: - Load

    /// Runs cactusInit on a BACKGROUND thread — never blocks the UI.
    func loadModel() async {
        switch state {
        case .idle, .failed:
            break
        case .loading, .ready:
            print("[CactusManager] Already loading or loaded, skipping.")
            return
        }

        await MainActor.run { self.state = .loading }
        print("[CactusManager] Starting model load...")

        do {
            let path = try resolveModelPath()
            print("[CactusManager] Model path resolved: \(path)")

            // Run blocking cactusInit on the same serial Cactus queue used for inference.
            // [PERF] model_load scope includes waiting for the serial inference queue.
            let loadScope = PerfScope.begin("model_load")
            let handle: CactusModelT
            do {
                handle = try await runOnInferenceQueue {
                    print("[CactusManager] cactusInit starting...")
                    let h = try cactusInit(path, nil, false)
                    print("[CactusManager] cactusInit complete.")
                    return h
                }
            } catch {
                loadScope.end("result=error")
                throw error
            }
            PerfMonitor.shared.noteModelLoad()
            loadScope.end("result=ok")

            modelHandle = handle
            await MainActor.run { self.state = .ready }
            print("[CactusManager] Model ready.")

        } catch {
            await MainActor.run { self.state = .failed(error.localizedDescription) }
            print("[CactusManager] Load failed: \(error)")
        }
    }

    func unloadModel() {
        if let h = modelHandle {
            let releaseStart = DispatchTime.now().uptimeNanoseconds
            cactusDestroy(h)
            PerfMonitor.shared.noteModelRelease()
            PerfMonitor.log("model_unload", "ms=\(PerfMonitor.ms(since: releaseStart))")
        }
        modelHandle = nil
        state = .idle
    }

    func releaseModelForMemoryPressure() async {
        let handle = modelHandle
        modelHandle = nil
        await MainActor.run { self.state = .idle }

        guard let handle else { return }
        let sendableHandle = SendableModelHandle(rawValue: handle)
        await withCheckedContinuation { continuation in
            inferenceQueue.async {
                print("[CactusManager] Releasing model after memory pressure...")
                let releaseStart = DispatchTime.now().uptimeNanoseconds
                let footprintBefore = PerfMonitor.physFootprintBytes()
                cactusDestroy(sendableHandle.rawValue)
                PerfMonitor.shared.noteModelRelease()
                PerfMonitor.log("model_release", "ms=\(PerfMonitor.ms(since: releaseStart)) footprint_before_mb=\(PerfMonitor.mb(footprintBefore))")
                print("[CactusManager] Model released.")
                continuation.resume()
            }
        }
    }

    // MARK: - Inference

    /// Text-only completion — runs on background thread, streams tokens to Xcode console.
    func complete(
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        onToken: ((String) -> Void)? = nil
    ) async throws -> String {
        let handle = try requireHandle()

        let messages = [
            ChatMessagePayload(role: "system", content: systemPrompt),
            ChatMessagePayload(role: "user", content: userMessage)
        ]
        // repetition_penalty 1.0 disables it. Cactus subtracts log(penalty) once per occurrence
        // of each of the last 128 sampled tokens (cactus/engine/engine_model.cpp), so in long
        // JSON the repeated `":"`, `","` and quote tokens get pushed down until the model emits
        // `}` or `>` instead (bench/results/phase2-diag-2026-10-21.md).
        let options: [String: Any] = [
            "max_tokens": maxTokens,
            "temperature": temperature,
            "top_p": 0.9,
            "repetition_penalty": 1.0,
            "auto_handoff": false
        ]

        let messagesJSON = try orderedMessagesJSON(messages)
        let optionsJSON  = try jsonString(options)

        print("[CactusManager] Inference queued (maxTokens: \(maxTokens))...")

        return try await runOnInferenceQueue {
            print("[CactusManager] Inference start (maxTokens: \(maxTokens))...")
            let inferenceScope = PerfScope.begin("inference", extra: "kind=text max_tokens=\(maxTokens) messages_chars=\(messagesJSON.count) messages_hash=\(PerfMonitor.fnv1a(messagesJSON))")
            let raw: String
            do {
                raw = try cactusComplete(
                    handle,
                    messagesJSON,
                    optionsJSON,
                    nil,
                    onToken.map { cb in { token, _ in
                        cb(token)
                        print("[Gemma]", token, terminator: "")
                    }}
                )
            } catch {
                inferenceScope.end("result=error")
                throw error
            }
            PerfMonitor.shared.noteInference(vision: false)
            inferenceScope.end("result=ok \(PerfMonitor.cactusMetrics(from: raw, maxTokens: maxTokens))")
            PerfMonitor.logResponsePreview(kind: "text", raw: raw)
            let text = Self.extractResponse(from: raw)
            print("\n[CactusManager] Inference done (\(text.count) chars)")
            return text
        }
    }

    /// Vision completion — runs on background thread.
    func visionComplete(
        systemPrompt: String,
        userMessage: String,
        imageData: Data,
        maxTokens: Int = 512
    ) async throws -> String {
        let handle = try requireHandle()

        let imageURL = try writeTemporaryJPEG(from: imageData)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let messages = [
            ChatMessagePayload(role: "system", content: systemPrompt),
            ChatMessagePayload(role: "user", content: userMessage, images: [imageURL.path])
        ]
        // Greedy and no repetition penalty (Cactus defaults it to 1.1); see `complete`.
        let options: [String: Any] = [
            "max_tokens": maxTokens,
            "temperature": 0,
            "repetition_penalty": 1.0,
            "auto_handoff": false
        ]

        let messagesJSON = try orderedMessagesJSON(messages)
        let optionsJSON  = try jsonString(options)

        print("[CactusManager] Vision inference queued...")

        return try await runOnInferenceQueue {
            print("[CactusManager] Vision inference start...")
            let inferenceScope = PerfScope.begin("inference", extra: "kind=vision max_tokens=\(maxTokens) messages_chars=\(messagesJSON.count) messages_hash=\(PerfMonitor.fnv1a(messagesJSON)) input_image_bytes=\(imageData.count) input_image_hash=\(PerfMonitor.fnv1a(imageData.base64EncodedString()))")
            let raw: String
            do {
                raw = try cactusComplete(handle, messagesJSON, optionsJSON, nil, nil)
            } catch {
                inferenceScope.end("result=error")
                throw error
            }
            PerfMonitor.shared.noteInference(vision: true)
            inferenceScope.end("result=ok \(PerfMonitor.cactusMetrics(from: raw, maxTokens: maxTokens))")
            PerfMonitor.logResponsePreview(kind: "vision", raw: raw)
            let text = Self.extractResponse(from: raw)
            print("[CactusManager] Vision inference done (\(text.count) chars)")
            return text
        }
    }

    // MARK: - Private helpers

    /// Unwrap the cactus JSON envelope: {"success":true,"response":"...", ...}
    /// Returns the inner `response` text, or the raw string if parsing fails.
    private static func extractResponse(from raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = dict["response"] as? String
        else {
            // Not a JSON envelope — return as-is (e.g. streaming mode)
            return raw
        }
        return response
    }

    private func requireHandle() throws -> CactusModelT {
        guard let h = modelHandle, isReady else { throw CactusError.modelNotLoaded }
        return h
    }

    private func runOnInferenceQueue<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// One chat message as sent to Cactus.
    private struct ChatMessagePayload {
        let role: String
        let content: String
        var images: [String]? = nil
    }

    /// Serializes chat messages with a fixed key order: role, content, images.
    ///
    /// Cactus's `parse_messages_json` (cactus/ffi/cactus_utils.h) only looks for
    /// `"content"` after `"role"`. Building messages as Swift dictionaries and passing
    /// them to JSONSerialization gave an unstable key order, so whenever `content` was
    /// emitted first Cactus silently dropped it (35 % of text inferences in
    /// bench/results/baseline-2026-10-21.md). Each value is still escaped by
    /// JSONSerialization, so only the key order changes.
    private func orderedMessagesJSON(_ messages: [ChatMessagePayload]) throws -> String {
        var objects: [String] = []
        for message in messages {
            let role = try jsonFragment(message.role)
            let content = try jsonFragment(message.content)
            var fields = ["\"role\":" + role, "\"content\":" + content]
            if let images = message.images {
                let imagesJSON = try jsonFragment(images)
                fields.append("\"images\":" + imagesJSON)
            }
            objects.append("{" + fields.joined(separator: ",") + "}")
        }
        return ("[" + objects.joined(separator: ",") + "]")
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private func jsonFragment(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard let str = String(data: data, encoding: .utf8) else { throw CactusError.jsonEncoding }
        return str
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let str = String(data: data, encoding: .utf8) else { throw CactusError.jsonEncoding }
        return str.replacingOccurrences(of: "\\/", with: "/")
    }

    private func writeTemporaryJPEG(from imageData: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cactus-image-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        let jpegData = Self.resizedJPEGData(from: imageData, maxDimension: 896, compressionQuality: 0.62) ?? imageData
        try jpegData.write(to: url, options: .atomic)
        return url
    }

    private static func resizedJPEGData(
        from imageData: Data,
        maxDimension: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return autoreleasepool {
            let size = image.size
            let longestSide = max(size.width, size.height)
            guard longestSide > 0 else { return nil }

            let scale = min(1, maxDimension / longestSide)
            let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return resized.jpegData(compressionQuality: compressionQuality)
        }
    }

    private func resolveModelPath() throws -> String {
        for modelDirName in modelDirCandidates {
            // 1. App bundle (production) - embedded model directory
            if let p = Bundle.main.url(forResource: modelDirName, withExtension: nil)?.path,
               FileManager.default.fileExists(atPath: p + "/config.txt") {
                print("[CactusManager] Using bundled model: \(modelDirName)")
                return p
            }
            // 2. Documents (sideloaded directory)
            let docsPath = modelDestURL(for: modelDirName).path
            if FileManager.default.fileExists(atPath: docsPath + "/config.txt") {
                print("[CactusManager] Using sideloaded model: \(modelDirName)")
                return docsPath
            }
            // 3. Developer path: cactus convert puts weights here
            let devPath = "/Users/weichengchen/Gemma4Good/cactus/weights/\(modelDirName)"
            if FileManager.default.fileExists(atPath: devPath + "/config.txt") {
                print("[CactusManager] Using dev model: \(modelDirName)")
                return devPath
            }
        }
        throw CactusError.modelFileNotFound
    }
}

// MARK: - Errors
enum CactusError: LocalizedError {
    case modelNotLoaded
    case modelFileNotFound
    case jsonEncoding
    case inferenceFailure(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "On-device model is not loaded. Please wait or check the model file."
        case .modelFileNotFound:
            return "Gemma 4 model folder not found. Expected a Cactus weights directory with config.txt."
        case .jsonEncoding:
            return "Failed to encode prompt as JSON."
        case .inferenceFailure(let msg):
            return "Inference failed: \(msg)"
        }
    }
}
