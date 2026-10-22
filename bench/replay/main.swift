// Replays logged iPhone health scans through LenientJSON + HealthReportVerifier on the Mac and
// scores them against the sample report ground truth (bench/README.md). Needs verbose logs.
//
// Build and run from the repo root:
//   swiftc -o /tmp/replay bench/replay/main.swift ios/Services/Providers/OnDevice/HealthReportVerifier.swift \
//     ios/Services/Providers/OnDevice/LenientJSON.swift ios/Models/HealthReport.swift
//   /tmp/replay ~/Gemma4Good/bench-logs/*.log

import Foundation

let truth: [String: (String, HealthStatus)] = ["glucose": ("115", .warning), "hba1c": ("6.1", .warning),
    "total_cholesterol": ("164", .normal), "hdl": ("81", .normal), "triglycerides": ("45", .normal),
    "ldl": ("74", .normal), "non_hdl": ("83", .normal), "chol_hdl_ratio": ("2.0", .normal)]
for path in CommandLine.arguments.dropFirst() {
    let log = try! String(contentsOfFile: path, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    var i = 0, scan = 0
    while i < log.count {
        guard log[i].hasPrefix("[PERF-RAW] begin source=ocr") else { i += 1; continue }
        var lines: [OCRLine] = []
        i += 1
        while !log[i].hasPrefix("[PERF-RAW] end source=ocr") {
            if let bar = log[i].range(of: " | ") {
                let head = log[i][..<bar.lowerBound].split(separator: " ")
                lines.append(OCRLine(text: String(log[i][bar.upperBound...]), midY: Double(head[0].dropFirst(2))!, height: Double(head[1].dropFirst(2))!))
            }
            i += 1
        }
        // The model output for this scan: next response_/failure block for health_ocr_text before next OCR block.
        var raw = ""
        var j = i
        while j < log.count, !log[j].hasPrefix("[PERF-RAW] begin source=ocr") {
            if log[j].hasPrefix("[PERF-RAW] begin source=response_health_ocr_text") || log[j].hasPrefix("[PERF-RAW] begin source=health_ocr_text ") {
                raw = log[j + 1]; break
            }
            j += 1
        }
        scan += 1
        let candidates = ((LenientJSON.parse(raw).dictionary?["metrics"] as? [[String: Any]]) ?? []).compactMap(MetricCandidate.init(json:))
        let text = HealthReportVerifier.verify(candidates, lines: lines, requireSameRow: false)
        let keys = Set(text.map(\.key))
        let table = HealthReportVerifier.verify(HealthReportVerifier.tableCandidates(lines: lines), lines: lines, requireSameRow: true)
        let final = text + table.filter { !keys.contains($0.key) }
        let ok = final.filter { m in truth[m.key].map { $0.0 == m.value && $0.1 == m.status } ?? false }
        let wrong = final.filter { m in truth[m.key].map { !($0.0 == m.value && $0.1 == m.status) } ?? false }
        let extra = final.filter { truth[$0.key] == nil }.map { "\($0.name)=\($0.value)" }
        print("\((path as NSString).lastPathComponent) scan\(scan) lines=\(lines.count) model=\(raw.isEmpty ? "none" : "\(candidates.count)") correct=\(ok.count)/8 wrong=\(wrong.map { "\($0.key)=\($0.value)" }) extra=\(extra)")
    }
}
