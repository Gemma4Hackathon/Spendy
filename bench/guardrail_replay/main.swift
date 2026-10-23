// Replays every Finance and Insights answer in logged device runs through OutputGuardrail and
// prints each sentence it would replace, so a new rule can be checked for false positives on
// real model output before it ships. Spending is the demo month (bench/README.md).
//
// Build and run from the repo root (verbose logs needed):
//   swiftc -o <scratch>/guardrail_replay bench/guardrail_replay/main.swift \
//     ios/Services/Providers/OnDevice/{OutputGuardrail,SpendingTargets,LenientJSON}.swift
//   <scratch>/guardrail_replay ~/Gemma4Good/bench-logs/phase3-*.log ~/Gemma4Good/bench-logs/phase4-*.log

import Foundation

let context = OutputGuardrail.Context(monthlyByCategory: [
    "Food Delivery": 1150, "Entertainment": 800, "Groceries": 520, "Fast Food": 395,
    "Late Night": 310, "Coffee": 285, "Convenience Store": 215, "Sugary Drinks": 150,
], extra: [3825, 1721])

/// Every string in a JSON answer with the key it sits under.
func sentences(_ object: Any, key: String = "") -> [(key: String, text: String)] {
    if let dict = object as? [String: Any] { return dict.flatMap { sentences($0.value, key: $0.key) } }
    if let array = object as? [Any] { return array.flatMap { sentences($0, key: key) } }
    if let text = object as? String { return [(key, text)] }
    return []
}

var checked = 0, flagged = 0
for path in CommandLine.arguments.dropFirst() {
    let log = try! String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n")
    var answer: [String]? = nil
    var source = ""
    for line in log {
        if line.hasPrefix("[PERF-RAW] begin source=response_finance") || line.hasPrefix("[PERF-RAW] begin source=response_insights") {
            answer = []
            source = line.contains("finance") ? "finance" : "insights"
        } else if line.hasPrefix("[PERF-RAW] end"), let lines = answer {
            answer = nil
            guard let dict = LenientJSON.parse(lines.joined(separator: "\n")).dictionary else { continue }
            for (key, text) in sentences(dict) {
                checked += 1
                let violations = OutputGuardrail.check(text, context: context, isOutcome: key == "expectedOutcome")
                guard !violations.isEmpty else { continue }
                flagged += 1
                print((path as NSString).lastPathComponent, source, key, violations.map(\.rawValue), "|", text)
            }
        } else {
            answer?.append(line)
        }
    }
}
print("checked=\(checked) flagged=\(flagged)")
