import Foundation

// MARK: - Insights context and prompt
// Pure logic shared by the app, `swift test` and the Mac harness (bench/mac_insights), so a
// prompt can be run on the Mac with Gemma 4 before it goes to the iPhone. The harness checks
// it builds the same messages as the device (`messages_hash` in the [PERF] log).

// MARK: - Context computed in Swift

/// Everything the result needs that is not writing: scores, amounts, and which spending
/// category and health metric each finding is about. Computed once, used for the prompt
/// and the result, so the model never has to copy numbers back.
nonisolated struct InsightContext {
    struct Finding {
        let icon: String
        let accentColor: String
        let cause: String
        let metric: HealthMetric?
        /// "Glucose: 115mg/dL", as the prompt names the metric.
        let metricLabel: String
        /// The spending category and its monthly total, when there is spending.
        let category: String?
        let monthly: Int?

        // Swift-written text for advice the guardrail rejects.

        var safeCauseDetail: String {
            guard let category, let monthly else { return "Spending in this category adds up over the month." }
            return "\(category) spending was NT$\(monthly) this month, about NT$\(SpendingTargets.weeklyPace(Double(monthly))) a week."
        }

        var safeRisk: String {
            "This spending pattern may contribute to \(metric?.name ?? metricLabel)."
        }

        func safeAction(_ variant: Int) -> InsightAction {
            guard let category, let monthly else {
                return InsightAction(title: "Set a 7-day limit", description: "Pick one repeat purchase to cap this week.",
                                     expectedOutcome: "One clear spending limit kept for 7 days.", timeframe: "7 days", difficulty: 1)
            }
            let pace = SpendingTargets.weeklyPace(Double(monthly))
            let cap = SpendingTargets.weeklyCap(Double(monthly))
            if variant == 0 {
                return InsightAction(title: "Cap \(category) at NT$\(cap)/week",
                                     description: "A weekly cap keeps \(category) about NT$\(max(0, pace - cap)) below the current pace.",
                                     expectedOutcome: "Save about NT$\(max(0, pace - cap)) in 7 days.", timeframe: "7 days", difficulty: 2)
            }
            return InsightAction(title: "Skip one \(category) purchase",
                                 description: "Replacing one repeat purchase is an easy first step.",
                                 expectedOutcome: "One fewer \(category) purchase in 7 days.", timeframe: "7 days", difficulty: 1)
        }
    }

    let riskScore: Int
    let monthlyAtRisk: Double
    let findings: [Finding]
    /// Weekly pace, cap and saving per finding category, computed in Swift.
    let weeklyTargets: [String]
    /// Abnormal metric names for the action plan, e.g. "Glucose, Hemoglobin A1c".
    let targetMetric: String
    /// NT$ amounts the advice may mention (see OutputGuardrail).
    let guardrail: OutputGuardrail.Context

    init(spending: [SpendingEntry], health: HealthReport) {
        let totalSpend = spending.reduce(0) { $0 + $1.amount }
        let abnormal = health.metrics.filter { $0.status != .normal }
        riskScore = min(95, 40 + abnormal.count * 12)
        monthlyAtRisk = Double(Int(totalSpend * 0.45))

        // Diet-related categories first, so each finding links spending to a health metric
        // plausibly (an Entertainment-to-HbA1c link reads as nonsense in a demo).
        let dietRelated: Set<SpendingCategory> = [.beverages, .foodDelivery, .fastFood, .food, .convenienceStore, .coffee, .lateNight]
        let byAmount = SpendingCategory.allCases.compactMap { cat -> (category: SpendingCategory, total: Int)? in
            let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return (cat, Int(total))
        }.sorted { $0.total > $1.total }
        let topCats = (byAmount.filter { dietRelated.contains($0.category) } + byAmount.filter { !dietRelated.contains($0.category) })
            .prefix(2)
            .map { ($0.category.rawValue, $0.total) }
        // Every diet-related category gets a target, so the model never has to invent one.
        let targetCats = byAmount.filter { dietRelated.contains($0.category) }
        weeklyTargets = (targetCats.isEmpty ? Array(byAmount.prefix(2)) : targetCats)
            .map { SpendingTargets.summary(category: $0.category.rawValue, monthlyAmount: Double($0.total)) }
        guardrail = OutputGuardrail.Context(monthlyByCategory: Dictionary(uniqueKeysWithValues: byAmount.map { ($0.category.rawValue, $0.total) }),
                                            extra: [Int(totalSpend), Int(totalSpend * 0.45)])
        let cat1 = topCats.first.map { "\($0.0) NT$\($0.1)" } ?? "Food Delivery NT$1500"
        let cat2 = topCats.dropFirst().first.map { "\($0.0) NT$\($0.1)" } ?? "Drinks NT$800"

        // Abnormal metrics first, so findings explain what the report flagged.
        let ranked = abnormal + health.metrics.filter { $0.status == .normal }
        let label: (HealthMetric?, String) -> String = { metric, fallback in
            metric.map { "\($0.name): \($0.value)\($0.unit)" } ?? fallback
        }
        findings = [
            Finding(icon: "fork.knife", accentColor: "amber", cause: "\(cat1) spending pattern",
                    metric: ranked.first, metricLabel: label(ranked.first, "Blood Sugar: 110 mg/dL"),
                    category: topCats.first?.0, monthly: topCats.first?.1),
            Finding(icon: "moon.fill", accentColor: "red", cause: "\(cat2) spending pattern",
                    metric: ranked.dropFirst().first, metricLabel: label(ranked.dropFirst().first, "Blood Pressure: 130/85"),
                    category: topCats.dropFirst().first?.0, monthly: topCats.dropFirst().first?.1)
        ]
        targetMetric = abnormal.isEmpty
            ? "Blood pressure, glucose, triglycerides"
            : abnormal.prefix(3).map(\.name).joined(separator: ", ")
    }
}

nonisolated enum InsightPrompt {

    static func system(isRetry: Bool) -> String {
        let retryInstruction = isRetry
            ? "The previous answer used the wrong schema. Correct it now and output only the required JSON object."
            : "Output only the required JSON object."

        return """
        You are an on-device health-and-spending insight engine.
        \(retryInstruction)
        The response MUST begin with { and end with }.
        Required top-level keys exactly: actionPlan, findings.
        actionPlan MUST contain movement and food objects.
        Each actionPlan object MUST contain title, recommendation, whyItMatters.
        The findings array MUST contain 2 objects, each with causeDetail, risk, and exactly 2 actions.
        Each action MUST contain title, description, expectedOutcome.
        Do not output query_details, example_data, schema descriptions, markdown, comments, or text outside JSON.
        Do not use placeholders such as REPLACE.
        Do not use emojis.
        Use only the supplied Spending and Health values.
        Make actions practical and concise: what to do, why it matters, and what can change in 7 days.
        """
    }

    static func user(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport,
        context: InsightContext
    ) -> String {
        let spendingLines = spendingLines(spending)
        let healthLines = healthLines(health)

        let finding = { (index: Int) -> String in
            let frame = context.findings[index]
            let action = #"{"title":"REPLACE short action","description":"REPLACE why this helps","expectedOutcome":"REPLACE 7-day result"}"#
            return #"{"causeDetail":"REPLACE one sentence about \#(frame.cause)","risk":"REPLACE one sentence on how it affects \#(frame.metricLabel)","actions":[\#(action),\#(action)]}"#
        }

        return """
        TASK:
        Generate health-and-spending risk insights using the data below.

        DATA:
        User: \(profile.age)yo \(profile.gender), BMI \(String(format: "%.1f", profile.bmi)).
        Spending this month (monthly totals): \(spendingLines).
        Health metrics: \(healthLines).
        Weekly targets: \(context.weeklyTargets.joined(separator: "; ")).

        REQUIRED OUTPUT:
        Return one JSON object matching this schema exactly:
        {"actionPlan":{"movement":{"title":"REPLACE movement title","recommendation":"REPLACE with daily walking, jogging, or cycling duration","whyItMatters":"REPLACE with concise may help support language tied to \(context.targetMetric)"},"food":{"title":"REPLACE food title","recommendation":"REPLACE with specific delivery, fast food, sugar drink, or grocery swap target","whyItMatters":"REPLACE with concise helps reduce exposure language tied to \(context.targetMetric)"}},"findings":[\(finding(0)),\(finding(1))]}

        RULES:
        Replace every REPLACE value with a concrete sentence based on DATA.
        Every action title must start with a verb and include either a frequency, limit, or NT$ target.
        Use the Weekly targets for every NT$ cap and saving. Never set a category to zero.
        A 7-day saving is the weekly saving in Weekly targets, never a monthly total.
        Every action description must connect the spending behavior to the health metric.
        Every expectedOutcome must be a spending or habit result measurable in 7 days (NT$ saved, drinks or orders skipped, minutes walked), never a change in a lab value or a diagnosis.
        Every risk sentence must say the habit may contribute, not that it caused the lab value.
        Do not create generic example data.
        Do not include query_details or example_data.
        """
    }

    static func retry(_ userMessage: String) -> String {
        """
        \(userMessage)

        RETRY CONSTRAINTS:
        Your previous response was invalid because it did not contain top-level actionPlan and findings.
        Output only the required JSON object now.
        The first character must be {.
        Include actionPlan.movement and actionPlan.food with title, recommendation, whyItMatters.
        The top-level object must contain a findings array with exactly 2 findings.
        Each finding must contain causeDetail, risk, and exactly 2 concise actions.
        """
    }

    /// "Sugary Drinks NT$150, Food Delivery NT$1150, ..." in category order.
    static func spendingLines(_ spending: [SpendingEntry]) -> String {
        SpendingCategory.allCases.compactMap { cat -> String? in
            let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return "\(cat.rawValue) NT$\(Int(total))"
        }.joined(separator: ", ")
    }

    static func healthLines(_ health: HealthReport) -> String {
        health.metrics.map {
            "\($0.name) \($0.value)\($0.unit) (normal \($0.normalRange), status \($0.status.rawValue))"
        }.joined(separator: "; ")
    }
}
