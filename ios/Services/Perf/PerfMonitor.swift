import Foundation
import os

// MARK: - PerfMonitor
// Measurement-only instrumentation. Nothing in here changes app behavior:
// it reads clocks and memory counters, prints one-line "[PERF]" records to the
// console, and emits os_signpost intervals so Instruments timelines line up.
//
// Console format (one record per line, greppable):
//   [PERF] event=<name> key=value key=value ...
//
// Value logging (extracted metric names/values) is OFF by default because it can
// contain health data. Enable it per run by adding the launch argument
// `-SpendyPerfVerbose` in the Xcode scheme (Run > Arguments).

final class PerfMonitor: @unchecked Sendable {

    static let shared = PerfMonitor()

    static let signposter = OSSignposter(subsystem: "com.gemma4good.Spendy", category: "Perf")

    /// True when launched with an argument containing `SpendyPerfVerbose`
    /// (tolerates a missing or auto-corrected leading dash) or with the
    /// environment variable `SPENDY_PERF_VERBOSE=1`.
    static let verbose: Bool = {
        let info = ProcessInfo.processInfo
        return info.arguments.contains { $0.contains("SpendyPerfVerbose") }
            || info.environment["SPENDY_PERF_VERBOSE"] == "1"
    }()

    private let lock = NSLock()

    // Cumulative counters since launch. Scopes report deltas.
    private(set) var inferenceCount = 0
    private(set) var visionInferenceCount = 0
    private(set) var modelLoadCount = 0
    private(set) var modelReleaseCount = 0

    // Peak / minimum trackers for active scopes, keyed by scope id.
    private var activePeaks: [UUID: (peakFootprint: UInt64, minAvailable: Int)] = [:]
    private var sampler: DispatchSourceTimer?
    private let samplerQueue = DispatchQueue(label: "Spendy.PerfMonitor.sampler", qos: .utility)

    /// Sampling period for peak-memory tracking while any scope is active.
    private let sampleIntervalMs = 100

    private init() {}

    // MARK: Counters

    func noteInference(vision: Bool) {
        lock.lock(); defer { lock.unlock() }
        inferenceCount += 1
        if vision { visionInferenceCount += 1 }
    }

    func noteModelLoad() {
        lock.lock(); defer { lock.unlock() }
        modelLoadCount += 1
    }

    func noteModelRelease() {
        lock.lock(); defer { lock.unlock() }
        modelReleaseCount += 1
    }

    struct CounterSnapshot {
        let inferences: Int
        let visionInferences: Int
        let modelLoads: Int
        let modelReleases: Int
    }

    func counters() -> CounterSnapshot {
        lock.lock(); defer { lock.unlock() }
        return CounterSnapshot(
            inferences: inferenceCount,
            visionInferences: visionInferenceCount,
            modelLoads: modelLoadCount,
            modelReleases: modelReleaseCount
        )
    }

    // MARK: Peak tracking

    fileprivate func startTracking(_ id: UUID) {
        let footprint = PerfMonitor.physFootprintBytes()
        let available = PerfMonitor.availableMemoryBytes()
        lock.lock()
        activePeaks[id] = (peakFootprint: footprint, minAvailable: available)
        let needsSampler = sampler == nil
        lock.unlock()
        if needsSampler { startSampler() }
    }

    fileprivate func stopTracking(_ id: UUID) -> (peakFootprint: UInt64, minAvailable: Int) {
        sampleNow()
        lock.lock()
        let result = activePeaks.removeValue(forKey: id) ?? (peakFootprint: 0, minAvailable: 0)
        let shouldStop = activePeaks.isEmpty
        let timer = shouldStop ? sampler : nil
        if shouldStop { sampler = nil }
        lock.unlock()
        timer?.cancel()
        return result
    }

    private func startSampler() {
        let timer = DispatchSource.makeTimerSource(queue: samplerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(sampleIntervalMs))
        timer.setEventHandler { [weak self] in self?.sampleNow() }
        lock.lock()
        if sampler == nil {
            sampler = timer
            lock.unlock()
            timer.resume()
        } else {
            lock.unlock()
        }
    }

    private func sampleNow() {
        let footprint = PerfMonitor.physFootprintBytes()
        let available = PerfMonitor.availableMemoryBytes()
        lock.lock()
        for (key, value) in activePeaks {
            activePeaks[key] = (peakFootprint: max(value.peakFootprint, footprint), minAvailable: min(value.minAvailable, available))
        }
        lock.unlock()
    }

    // MARK: Memory readings

    /// Physical footprint of this process (the number jetsam evaluates), in bytes.
    static func physFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Bytes this process can still allocate before hitting its jetsam limit.
    static func availableMemoryBytes() -> Int {
        Int(os_proc_available_memory())
    }

    static func mb<T: BinaryInteger>(_ bytes: T) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576.0)
    }

    static func ms(since start: UInt64) -> String {
        let elapsedNs = DispatchTime.now().uptimeNanoseconds &- start
        return String(format: "%.1f", Double(elapsedNs) / 1_000_000.0)
    }

    // MARK: Launch / input identity

    /// One line at app start so every log states its build configuration and flags.
    static func logLaunch() {
        #if DEBUG
        let config = "Debug"
        #else
        let config = "Release"
        #endif
        let args = ProcessInfo.processInfo.arguments.dropFirst().joined(separator: "|")
        log("app_launch", "config=\(config) verbose=\(verbose) vision_tokens=\(bundledVisionTokenBudget()) launch_args=\"\(args)\"")
    }

    /// Verbose-only: first characters of a model response, newlines escaped.
    /// Used to see what short or invalid outputs actually contain.
    static func logResponsePreview(kind: String, raw: String) {
        guard verbose else { return }
        let text: String
        if let data = raw.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let response = dict["response"] as? String {
            text = response
        } else {
            text = raw
        }
        let preview = text.prefix(240)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "'")
        print("[PERF-RESULT] response_preview kind=\(kind) chars=\(text.count) text=\"\(preview)\"")
    }

    /// A model response that a provider failed to parse. The one-line record (no content)
    /// is always printed. Verbose-only: the full raw response and the extracted JSON
    /// candidate follow verbatim (no truncation, no escaping) between [PERF-RAW] markers.
    static func logParseFailure(source: String, reason: String, raw: String, cleaned: String, error: Error? = nil) {
        log("parse_failure", "source=\(source) reason=\(reason) raw_chars=\(raw.count) cleaned_chars=\(cleaned.count)")
        guard verbose else { return }
        let detail = error.map { error -> String in
            let nsError = error as NSError
            let text = nsError.userInfo[NSDebugDescriptionErrorKey] as? String ?? nsError.localizedDescription
            return text.replacingOccurrences(of: "\"", with: "'")
        } ?? ""
        print("[PERF-RAW] begin source=\(source) reason=\(reason) error=\"\(detail)\"")
        print(raw)
        print("[PERF-RAW] cleaned source=\(source)")
        print(cleaned)
        print("[PERF-RAW] end source=\(source)")
    }

    /// Outcome of LenientJSON on a model response: a `json_repair` record when repairs
    /// were applied, and `logParseFailure` when the text still is not JSON.
    static func logJSONParse(source: String, raw: String, result: LenientJSON.Result) {
        if !result.fixes.isEmpty {
            log("json_repair", "source=\(source) fixes=\(result.fixSummary) parsed=\(result.object != nil)")
        }
        if result.object == nil {
            logParseFailure(source: source, reason: "invalid_json", raw: raw, cleaned: result.candidate, error: result.error)
        } else {
            // Full parsed output too, for quality review and per-field token attribution.
            logRawText(source: "response_\(source)", text: raw)
        }
    }

    /// Verbose-only: a block of text printed verbatim between [PERF-RAW] markers.
    static func logRawText(source: String, text: String) {
        guard verbose else { return }
        print("[PERF-RAW] begin source=\(source)")
        print(text)
        print("[PERF-RAW] end source=\(source)")
    }

    /// Reads `vision_default_output_length` from the bundled model's config.txt, so each
    /// log records which visual-token budget the app actually shipped with.
    static func bundledVisionTokenBudget() -> String {
        guard let url = Bundle.main.url(forResource: "gemma-4-e2b-m23k-cot-sft-lora-int4", withExtension: nil)?
                .appendingPathComponent("config.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "na" }
        for line in text.split(separator: "\n") where line.hasPrefix("vision_default_output_length=") {
            return String(line.dropFirst("vision_default_output_length=".count))
        }
        return "na"
    }

    /// Stable 64-bit FNV-1a hash of a prompt, used to prove two runs had identical input.
    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: Logging

    static func log(_ event: String, _ fields: String = "") {
        let footprint = mb(physFootprintBytes())
        let available = mb(max(availableMemoryBytes(), 0))
        let tail = fields.isEmpty ? "" : " \(fields)"
        print("[PERF] event=\(event)\(tail) footprint_mb=\(footprint) available_mb=\(available)")
    }

    /// Parses the timing fields Cactus already returns in its JSON envelope
    /// and returns them as a "key=value" string. Read-only; never alters the response.
    static func cactusMetrics(from raw: String, maxTokens: Int? = nil) -> String {
        guard let data = raw.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "cactus_json=unparsed" }

        func number(_ key: String) -> String {
            if let n = dict[key] as? NSNumber { return n.stringValue }
            return "na"
        }
        let responseChars = (dict["response"] as? String)?.count ?? -1
        let thinkingChars = (dict["thinking"] as? String)?.count ?? 0
        let success = (dict["success"] as? Bool).map { $0 ? "true" : "false" } ?? "na"
        // Decoding stopped at the token cap, so the response is cut off.
        let hitMaxTokens: String = {
            guard let maxTokens, let decoded = (dict["decode_tokens"] as? NSNumber)?.intValue else { return "na" }
            return decoded >= maxTokens ? "true" : "false"
        }()

        return [
            "success=\(success)",
            "ttft_ms=\(number("time_to_first_token_ms"))",
            "cactus_total_ms=\(number("total_time_ms"))",
            "prefill_tps=\(number("prefill_tps"))",
            "decode_tps=\(number("decode_tps"))",
            "prefill_tokens=\(number("prefill_tokens"))",
            "decode_tokens=\(number("decode_tokens"))",
            "cactus_ram_mb=\(number("ram_usage_mb"))",
            "response_chars=\(responseChars)",
            "thinking_chars=\(thinkingChars)",
            "hit_max_tokens=\(hitMaxTokens)",
            "thermal_state=\(thermalStateName())"
        ].joined(separator: " ")
    }

    /// Device thermal state at the end of an inference; throttling slows decode.
    static func thermalStateName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - PerfScope
// Times one user-visible operation (a health scan, an insight generation, ...)
// and reports how many inferences / model loads / releases happened inside it,
// plus the peak footprint and lowest jetsam headroom sampled during it.

final class PerfScope: @unchecked Sendable {
    private let name: String
    private let id = UUID()
    private let start = DispatchTime.now().uptimeNanoseconds
    private let startCounters: PerfMonitor.CounterSnapshot
    private let signpostState: OSSignpostIntervalState
    private var ended = false

    private init(name: String, extra: String) {
        self.name = name
        self.startCounters = PerfMonitor.shared.counters()
        self.signpostState = PerfMonitor.signposter.beginInterval("Scope", id: PerfMonitor.signposter.makeSignpostID(), "\(name, privacy: .public)")
        PerfMonitor.shared.startTracking(id)
        PerfMonitor.log("\(name)_begin", extra)
    }

    static func begin(_ name: String, extra: String = "") -> PerfScope {
        PerfScope(name: name, extra: extra)
    }

    func end(_ extra: String = "") {
        guard !ended else { return }
        ended = true
        let peaks = PerfMonitor.shared.stopTracking(id)
        let now = PerfMonitor.shared.counters()
        PerfMonitor.signposter.endInterval("Scope", signpostState)
        let fields = [
            "total_ms=\(PerfMonitor.ms(since: start))",
            "inferences=\(now.inferences - startCounters.inferences)",
            "vision_inferences=\(now.visionInferences - startCounters.visionInferences)",
            "model_loads=\(now.modelLoads - startCounters.modelLoads)",
            "model_releases=\(now.modelReleases - startCounters.modelReleases)",
            "peak_footprint_mb=\(PerfMonitor.mb(peaks.peakFootprint))",
            "min_available_mb=\(PerfMonitor.mb(max(peaks.minAvailable, 0)))",
            extra
        ].filter { !$0.isEmpty }.joined(separator: " ")
        PerfMonitor.log("\(name)_end", fields)
    }
}
