// Builds the Insights messages JSON the app sends to Gemma 4, from a logged device run, so
// bench/mac_insights/run.py can run the same prompt on the Mac. The health report is rebuilt
// from the run's last logged scan (OCR lines + model answer) the way the extractor builds it;
// spending is the demo month (Finance in bench/README.md); the profile is UserProfile.demo.
// Prints messages_chars and messages_hash: they must equal the device's `inference_begin`
// record for the Insights call, otherwise the Mac is not running the device's prompt.
//
// Build and run from the repo root (verbose log needed):
//   swiftc -o <scratch>/prompt bench/mac_insights/main.swift ios/Models/{HealthReport,SpendingEntry,UserProfile,InsightResult}.swift \
//     ios/Services/Providers/OnDevice/{HealthReportVerifier,LenientJSON,SpendingTargets,OutputGuardrail,InsightComposer}.swift
//   <scratch>/prompt ~/Gemma4Good/bench-logs/phase4-r1.log <scratch>/messages.json

import Foundation

let args = CommandLine.arguments
let log = try! String(contentsOfFile: args[1], encoding: .utf8)
    .replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

// Last scan with a text-model answer (a failed scan leaves the previous report in place):
// its OCR lines and the answer.
var lines: [OCRLine] = []
var answer = ""
var pending: [OCRLine] = []
var i = 0
while i < log.count {
    if log[i].hasPrefix("[PERF-RAW] begin source=ocr") {
        pending = []
        i += 1
        while !log[i].hasPrefix("[PERF-RAW] end source=ocr") {
            if let bar = log[i].range(of: " | ") {
                let head = log[i][..<bar.lowerBound].split(separator: " ")
                pending.append(OCRLine(text: String(log[i][bar.upperBound...]),
                                     midY: Double(head[0].dropFirst(2))!, height: Double(head[1].dropFirst(2))!))
            }
            i += 1
        }
    } else if log[i].hasPrefix("[PERF-RAW] begin source=response_health_ocr_text") {
        lines = pending
        answer = log[i + 1]
    }
    i += 1
}

// Same order as OnDeviceHealthReportExtractor: model values first, then table rows it left out.
let candidates = ((LenientJSON.parse(answer).dictionary?["metrics"] as? [[String: Any]]) ?? []).compactMap(MetricCandidate.init(json:))
let text = HealthReportVerifier.verify(candidates, lines: lines, requireSameRow: false)
let keys = Set(text.map(\.key))
let table = HealthReportVerifier.verify(HealthReportVerifier.tableReadings(lines: lines).map(\.candidate), lines: lines, requireSameRow: true)
let metrics = (text + table.filter { !keys.contains($0.key) }).map {
    HealthMetric(name: $0.name, value: $0.value, unit: $0.unit, normalRange: $0.normalRange, status: $0.status, icon: "", progress: 0)
}
let health = HealthReport(metrics: metrics, reportDate: Date(), labName: "", evidenceTrace: [])

let demoMonth: [(SpendingCategory, Double)] = [
    (.foodDelivery, 1150), (.entertainment, 800), (.groceries, 520), (.fastFood, 395),
    (.lateNight, 310), (.coffee, 285), (.convenienceStore, 215), (.beverages, 150),
]
let spending = demoMonth.map { SpendingEntry(title: $0.0.rawValue, amount: $0.1, category: $0.0) }

let context = InsightContext(spending: spending, health: health)
let messages = [
    ("system", InsightPrompt.system(isRetry: false)),
    ("user", InsightPrompt.user(profile: .demo, spending: spending, health: health, context: context)),
]

// CactusManager.orderedMessagesJSON: "role" before "content", values escaped by JSONSerialization.
func fragment(_ value: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), encoding: .utf8)!
}
let json = ("[" + messages.map { "{\"role\":\(fragment($0.0)),\"content\":\(fragment($0.1))}" }.joined(separator: ",") + "]")
    .replacingOccurrences(of: "\\/", with: "/")

// PerfMonitor.fnv1a
var hash: UInt64 = 0xcbf29ce484222325
for byte in json.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }

try! json.write(toFile: args[2], atomically: true, encoding: .utf8)
print("metrics=\(metrics.count) messages_chars=\(json.count) messages_hash=\(String(hash, radix: 16))")
