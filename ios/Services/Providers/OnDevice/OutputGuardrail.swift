import Foundation

// MARK: - OutputGuardrail
// Checks advice sentences written by the on-device model before they are shown. The model is
// good at wording and bad at numbers: on device it wrote a NT$765/week cap for an NT$800 month,
// called a monthly total "weekly", told the user to cut categories to zero and promised lab
// values would improve in 7 days. Every NT$ amount must be one Swift computed; a field that
// fails is replaced by Swift-written text by the caller.

nonisolated enum OutputGuardrail {

    enum Violation: String {
        case unknownAmount = "unknown_amount"
        case zeroTarget = "zero_target"
        case monthlyAsWeekly = "monthly_as_weekly"
        case labPromise = "lab_promise"
        case wrongCategory = "wrong_category"
        case causalClaim = "causal_claim"
        case offTopic = "off_topic"
    }

    struct Context {
        /// Every NT$ amount the text may mention: totals, weekly paces, caps and savings.
        let allowedAmounts: Set<Int>
        /// Monthly totals; one next to "per week" or "in 7 days" is a unit error.
        let monthlyAmounts: Set<Int>
        /// Each category's monthly total, weekly pace, cap and saving, keyed by lowercased name.
        let amountsByCategory: [String: Set<Int>]
        /// Amounts not tied to one category (overall total, amount at risk).
        let sharedAmounts: Set<Int>

        /// Monthly totals per category name plus their weekly pace, cap and saving.
        init(monthlyByCategory: [String: Int], extra: [Int] = []) {
            var byCategory: [String: Set<Int>] = [:]
            for (category, monthly) in monthlyByCategory {
                let pace = SpendingTargets.weeklyPace(Double(monthly))
                let cap = SpendingTargets.weeklyCap(Double(monthly))
                byCategory[category.lowercased()] = [monthly, pace, cap, max(0, pace - cap)]
            }
            amountsByCategory = byCategory
            sharedAmounts = Set(extra)
            allowedAmounts = byCategory.values.reduce(Set(extra)) { $0.union($1) }
            monthlyAmounts = Set(monthlyByCategory.values)
        }
    }

    /// `isOutcome`: the text promises a 7-day result, where lab-value claims are not allowed.
    static func check(_ text: String, context: Context, isOutcome: Bool = false) -> [Violation] {
        var violations: [Violation] = []
        let amounts = ntAmounts(in: text)
        if amounts.contains(where: { !context.allowedAmounts.contains($0) }) {
            violations.append(.unknownAmount)
        }
        if matches(text, #"\b(limit|reduce|cut|cap|lower|bring)\b[^.;]{0,30}\bto (zero|0|nothing)\b"#)
            || matches(text, #"NT\$\s?0\b"#) || matches(text, #"\beliminat"#)
            || context.monthlyAmounts.contains(where: { cutsWholeMonth($0, in: text) }) {
            violations.append(.zeroTarget)
        }
        if amounts.contains(where: context.monthlyAmounts.contains),
           context.monthlyAmounts.contains(where: { monthlyLabelledWeekly($0, in: text) }) {
            violations.append(.monthlyAsWeekly)
        }
        // "Limit Late Night spending to NT$210 per week": 210 is the Food Delivery cap.
        if let category = onlyCategory(in: text, context: context),
           amounts.contains(where: { !context.amountsByCategory[category, default: []].contains($0) && !context.sharedAmounts.contains($0) }) {
            violations.append(.wrongCategory)
        }
        // "Late-night eating causes high glucose": a habit may contribute, it is not the diagnosis.
        if matches(text, #"\b(causes?|caused|leads? to|led to|results? in)\b"#),
           !matches(text, #"\b(may|can|could|might)\b"#) {
            violations.append(.causalClaim)
        }
        if isOutcome && promisesLabChange(text) {
            violations.append(.labPromise)
        }
        return violations
    }

    /// Checks groups of fields and keeps counts for the `[PERF] event=guardrail` record.
    struct Audit {
        let context: Context
        private(set) var checked = 0
        private(set) var replaced = 0
        private(set) var reasons: [String] = []

        init(context: Context) { self.context = context }

        /// True when every text passes. A failing group is counted as replaced. `offTopic`:
        /// the caller found the text is about something else (another spending category).
        mutating func passes(_ texts: [String], outcome: String? = nil, offTopic: Bool = false) -> Bool {
            checked += 1
            let violations = texts.flatMap { check($0, context: context) }
                + (outcome.map { check($0, context: context, isOutcome: true) } ?? [])
                + (offTopic ? [.offTopic] : [])
            guard violations.isEmpty else {
                replaced += 1
                reasons += violations.map(\.rawValue)
                return false
            }
            return true
        }

        var summary: String {
            "checked=\(checked) replaced=\(replaced) reasons=\(reasons.isEmpty ? "none" : Set(reasons).sorted().joined(separator: ","))"
        }
    }

    // MARK: - Helpers

    private static func ntAmounts(in text: String) -> [Int] {
        let regex = try? NSRegularExpression(pattern: #"NT\$\s?(\d[\d,]*)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0].replacingOccurrences(of: ",", with: "")) }
        }
    }

    /// Spending categories a sentence names (lowercased).
    static func categories(in text: String, context: Context) -> [String] {
        context.amountsByCategory.keys.filter { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// The category a sentence is about, when it names exactly one.
    private static func onlyCategory(in text: String, context: Context) -> String? {
        let named = categories(in: text, context: context)
        return named.count == 1 ? named[0] : nil
    }

    /// "NT$1150 on Food Delivery weekly", "Save NT$1150 in 7 days", "weekly spend of NT$1150".
    private static func monthlyLabelledWeekly(_ amount: Int, in text: String) -> Bool {
        let week = #"(per week|/week|a week|weekly|each week|every week|this week|in 7 days|7-day)"#
        return matches(text, #"NT\$\s?\#(amount)\b[^.;,]{0,30}\#(week)"#)
            || matches(text, #"\#(week)[^.;,]{0,30}NT\$\s?\#(amount)\b"#)
    }

    /// "Reduce Food Delivery spending by NT$1150" when NT$1150 is the whole month.
    private static func cutsWholeMonth(_ amount: Int, in text: String) -> Bool {
        matches(text, #"\b(reduce|cut|lower|trim)\w*[^.;]{0,40}\bby NT\$\s?\#(amount)\b"#)
    }

    private static func promisesLabChange(_ text: String) -> Bool {
        let change = #"(improv|lower|reduc|normali[sz]|decreas|drop|better|stabili[sz])\w*"#
        let lab = #"(glucose|a1c|hba1c|cholesterol|ldl|hdl|triglycerides?|blood pressure|hemoglobin|blood sugar)"#
        return matches(text, #"\b\#(change)[^.;]{0,40}\b\#(lab)\b"#) || matches(text, #"\b\#(lab)\b[^.;]{0,30}\b\#(change)"#)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
