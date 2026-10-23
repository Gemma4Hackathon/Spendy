import Foundation

// MARK: - InsightProgress
// What the model has finished writing so far, read from the streamed (incomplete) JSON.
// LenientJSON closes the open strings and brackets of a partial answer, so a section counts
// as finished once the model has moved on to the next one. Insights take about 80 s on device;
// showing real progress beats a spinner.

nonisolated struct InsightProgress: Equatable, Sendable {

    enum Step: Int, CaseIterable, Sendable {
        case movement, food, finding1, finding2
    }

    /// Finished steps and the title the model wrote for each ("" when it wrote none).
    var finished: [Step: String] = [:]
    var tokens = 0
    /// The whole answer is written and is being checked in Swift.
    var isComplete = false

    /// The step the model is writing now; nil once every step is finished.
    var current: Step? { Step.allCases.first { finished[$0] == nil } }

    static func from(partial text: String, tokens: Int) -> InsightProgress {
        var progress = InsightProgress(tokens: tokens)
        let parsed = LenientJSON.parse(text)
        guard let dict = parsed.dictionary else { return progress }
        let complete = !parsed.fixes.contains("append_closer") && !parsed.fixes.contains("close_string")

        let plan = dict["actionPlan"] as? [String: Any]
        let findings = dict["findings"] as? [[String: Any]]
        func title(_ object: [String: Any]?) -> String { (object?["title"] as? String) ?? "" }

        if plan?["food"] != nil || findings != nil || complete {
            progress.finished[.movement] = title(plan?["movement"] as? [String: Any])
        }
        if findings != nil || complete {
            progress.finished[.food] = title(plan?["food"] as? [String: Any])
        }
        // A finding is one risk sentence; its actions are written in Swift (InsightComposer).
        for (index, step) in [Step.finding1, .finding2].enumerated() {
            let count = findings?.count ?? 0
            guard count > index + 1 || (complete && count > index) else { continue }
            progress.finished[step] = ""
        }
        progress.isComplete = complete && progress.current == nil
        return progress
    }
}
