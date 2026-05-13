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
    // Cactus uses its own weight format (directory with config.txt + tokenizer files + *.weights).
    private let modelDirName = "gemma-4-e2b-it"

    private var modelDestURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(modelDirName)
    }

    private init() {}

    // MARK: - Load

    /// Runs cactusInit on a BACKGROUND thread — never blocks the UI.
    func loadModel() async {
        guard case .idle = state else {
            print("[CactusManager] Already loading or loaded, skipping.")
            return
        }

        await MainActor.run { self.state = .loading }
        print("[CactusManager] Starting model load...")

        do {
            let path = try resolveModelPath()
            print("[CactusManager] Model path resolved: \(path)")

            // Run blocking cactusInit on background thread
            let handle = try await Task.detached(priority: .userInitiated) {
                print("[CactusManager] cactusInit starting...")
                let h = try cactusInit(path, nil, false)
                print("[CactusManager] cactusInit complete.")
                return h
            }.value

            modelHandle = handle
            await MainActor.run { self.state = .ready }
            print("[CactusManager] Model ready.")

        } catch {
            await MainActor.run { self.state = .failed(error.localizedDescription) }
            print("[CactusManager] Load failed: \(error)")
        }
    }

    func unloadModel() {
        if let h = modelHandle { cactusDestroy(h) }
        modelHandle = nil
        state = .idle
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

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": userMessage]
        ]
        let options: [String: Any] = [
            "max_tokens": maxTokens,
            "temperature": temperature,
            "top_p": 0.9,
            "repetition_penalty": 1.1,
            "auto_handoff": false
        ]

        let messagesJSON = try jsonString(messages)
        let optionsJSON  = try jsonString(options)

        print("[CactusManager] Inference start (maxTokens: \(maxTokens))...")

        return try await Task.detached(priority: .userInitiated) {
            let raw = try cactusComplete(
                handle,
                messagesJSON,
                optionsJSON,
                nil,
                onToken.map { cb in { token, _ in
                    cb(token)
                    print("[Gemma]", token, terminator: "")
                }}
            )
            let text = Self.extractResponse(from: raw)
            print("\n[CactusManager] Inference done (\(text.count) chars)")
            return text
        }.value
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

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            [
                "role": "user",
                "content": userMessage,
                "images": [imageURL.path]
            ]
        ]
        let options: [String: Any] = [
            "max_tokens": maxTokens,
            "temperature": 0.1,
            "auto_handoff": false
        ]

        let messagesJSON = try jsonString(messages)
        let optionsJSON  = try jsonString(options)

        print("[CactusManager] Vision inference start...")

        return try await Task.detached(priority: .userInitiated) {
            let raw = try cactusComplete(handle, messagesJSON, optionsJSON, nil, nil)
            let text = Self.extractResponse(from: raw)
            print("[CactusManager] Vision inference done (\(text.count) chars)")
            return text
        }.value
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

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let str = String(data: data, encoding: .utf8) else { throw CactusError.jsonEncoding }
        return str
    }

    private func writeTemporaryJPEG(from imageData: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cactus-image-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        let jpegData = UIImage(data: imageData)?.jpegData(compressionQuality: 0.92) ?? imageData
        try jpegData.write(to: url, options: .atomic)
        return url
    }

    private func resolveModelPath() throws -> String {
        // 1. App bundle (production) - embedded model directory
        if let p = Bundle.main.url(forResource: modelDirName, withExtension: nil)?.path,
           FileManager.default.fileExists(atPath: p + "/config.txt") {
            return p
        }
        // 2. Documents (sideloaded directory)
        let docsPath = modelDestURL.path
        if FileManager.default.fileExists(atPath: docsPath + "/config.txt") {
            return docsPath
        }
        // 3. Developer path: cactus convert puts weights here
        let devPath = "/Users/weichengchen/Gemma4Good/cactus/weights/\(modelDirName)"
        if FileManager.default.fileExists(atPath: devPath + "/config.txt") {
            print("[CactusManager] Using dev path: \(devPath)")
            return devPath
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
