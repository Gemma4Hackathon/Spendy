import Foundation

// MARK: - Insights: context, prompt and composition
// Gemma 4 writes only the parts that need wording: the movement and food plan, and why each
// spending habit may affect its health metric. Swift writes every fact and number: amounts,
// weekly caps, actions and 7-day outcomes. Phase 4 rounds: the model spent 578 tokens (122 s)
// restating amounts in every action, and its past mistakes (zero targets, monthly totals as
// weekly, lab-value promises, another category's cap) were all in those fields.
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
    }

    let riskScore: Int
    let monthlyAtRisk: Double
    let findings: [Finding]
    /// Weekly pace, cap and saving for the finding categories, computed in Swift.
    let weeklyTargets: [String]
    /// Abnormal metric names for the action plan, e.g. "Glucose, Hemoglobin A1c".
    let targetMetric: String
    /// Metrics the report flagged; all metrics when none is flagged.
    let flaggedMetrics: [HealthMetric]
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
        weeklyTargets = topCats.map { SpendingTargets.summary(category: $0.0, monthlyAmount: Double($0.1)) }
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
        flaggedMetrics = abnormal.isEmpty ? health.metrics : abnormal
    }
}

// MARK: - Prompt

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
        actionPlan MUST contain movement and food objects, each with title and recommendation.
        The findings array MUST contain 2 objects, each with risk.
        Do not output markdown, comments, or text outside JSON.
        Do not use placeholders such as REPLACE.
        Do not use emojis.
        Use only the supplied Spending and Health values.
        """
    }

    static func user(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport,
        context: InsightContext
    ) -> String {
        let metrics = context.flaggedMetrics.map {
            "\($0.name) \($0.value)\($0.unit) (normal \($0.normalRange))"
        }.joined(separator: "; ")
        let foodTarget = context.findings[0].category ?? "food delivery"
        // The habit and the metric are spelled out, so each sentence stays on its own finding.
        let risk = { (frame: InsightContext.Finding) -> String in
            let habit = frame.category.map { "frequent \($0) purchases" } ?? frame.cause
            let metric = frame.metric.map { "\($0.name) \($0.value)\($0.unit)" } ?? frame.metricLabel
            let reasons = likelyReasons(for: frame.metric?.name ?? frame.metricLabel)
            return #"{"risk":"REPLACE one sentence on how \#(habit) may contribute to \#(metric), naming one reason: \#(reasons)"}"#
        }

        return """
        TASK:
        Write a 7-day plan and explain two spending-and-health links using the data below.

        DATA:
        User: \(profile.age)yo \(profile.gender), BMI \(String(format: "%.1f", profile.bmi)).
        Spending this month (monthly totals): \(spendingLines(spending)).
        Health metrics flagged by the report: \(metrics).
        Weekly targets: \(context.weeklyTargets.joined(separator: "; ")).

        REQUIRED OUTPUT:
        Return one JSON object on a single line matching this schema exactly:
        {"actionPlan":{"movement":{"title":"REPLACE movement title","recommendation":"REPLACE daily walking, jogging, or cycling minutes"},"food":{"title":"REPLACE food title","recommendation":"REPLACE one swap or limit for \(foodTarget)"}},"findings":[\(risk(context.findings[0])),\(risk(context.findings[1]))]}

        RULES:
        Replace every REPLACE value with one concrete sentence based on DATA.
        Each title starts with a verb and has at most 8 words.
        If you name an NT$ amount, use the Weekly targets. Never set a category to zero.
        Each risk sentence says the habit may contribute, not that it caused the value.
        Do not promise that a lab value will improve or change.
        """
    }

    /// Diet reasons that plausibly relate to a metric, so a 2B model is not left to pick the
    /// physiology (phase 4 Mac run: "high sodium" given as a reason for HbA1c).
    static func likelyReasons(for metric: String) -> String {
        let name = metric.lowercased()
        if ["glucose", "a1c", "sugar"].contains(where: name.contains) { return "added sugar, refined carbs, or large portions" }
        if ["cholesterol", "ldl", "hdl", "triglyceride"].contains(where: name.contains) { return "fried food, fatty meat, or added sugar" }
        if name.contains("pressure") { return "salt or large portions" }
        return "added sugar, salt, or fried food"
    }

    static func retry(_ userMessage: String) -> String {
        """
        \(userMessage)

        RETRY CONSTRAINTS:
        Your previous response was invalid because it did not contain top-level actionPlan and findings.
        Output only the required JSON object now.
        The first character must be {.
        Include actionPlan.movement and actionPlan.food with title and recommendation.
        The top-level object must contain a findings array with exactly 2 findings, each with risk.
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

// MARK: - Swift-written text

nonisolated enum InsightTemplates {

    static func causeDetail(category: String?, monthly: Int?) -> String {
        guard let category, let monthly else { return "Spending in this category adds up over the month." }
        return "\(category) spending was NT$\(monthly) this month, about NT$\(SpendingTargets.weeklyPace(Double(monthly))) a week."
    }

    static func risk(metricName: String) -> String {
        "This spending pattern may contribute to \(metricName)."
    }

    /// A weekly cap (when it saves at least NT$10 a week) and a category-specific swap.
    static func actions(category: String?, monthly: Int?) -> [InsightAction] {
        guard let category, let monthly else {
            return [
                InsightAction(title: "Set a 7-day limit", description: "Pick one repeat purchase to cap this week.",
                              expectedOutcome: "One clear spending limit kept for 7 days.", timeframe: "7 days", difficulty: 1),
                swap(for: "Other"),
            ]
        }
        let pace = SpendingTargets.weeklyPace(Double(monthly))
        let cap = SpendingTargets.weeklyCap(Double(monthly))
        guard pace - cap >= 10 else {
            // Too small for a cap to mean anything ("save NT$0", a cap above the current pace).
            return [swap(for: category),
                    InsightAction(title: "Track every \(category) purchase this week",
                                  description: "Seeing each purchase makes the next one a choice.",
                                  expectedOutcome: "A full 7-day log of \(category) purchases.", timeframe: "7 days", difficulty: 1)]
        }
        return [
            InsightAction(title: "Cap \(category) at NT$\(cap)/week",
                          description: "\(category) runs about NT$\(pace) a week now; a NT$\(cap) cap saves NT$\(pace - cap).",
                          expectedOutcome: "Save about NT$\(pace - cap) in 7 days.", timeframe: "7 days", difficulty: 2),
            swap(for: category),
        ]
    }

    private static func swap(for category: String) -> InsightAction {
        let (title, why, outcome): (String, String, String) = switch category {
        case "Sugary Drinks":
            ("Swap 2 sugary drinks for water or unsweetened tea", "Each swap removes a drink's worth of added sugar.", "2 fewer sugary drinks in 7 days.")
        case "Food Delivery":
            ("Cook or pack lunch on 2 days", "Home meals make portions, oil and salt easier to control than delivery.", "2 fewer delivery orders in 7 days.")
        case "Fast Food":
            ("Replace 1 fast-food meal with a home meal", "Fast food is usually high in fried food, salt and refined carbs.", "1 fewer fast-food meal in 7 days.")
        case "Dining Out":
            ("Choose a grilled or steamed dish twice", "Grilled and steamed dishes carry less oil than fried ones.", "2 lighter restaurant meals in 7 days.")
        case "Convenience Store":
            ("Skip the snack add-on on 3 store visits", "Snack add-ons bring sugar and salt without much fullness.", "3 store visits without a snack in 7 days.")
        case "Coffee":
            ("Order 2 coffees without syrup or sugar", "Sweetened coffee drinks add sugar on top of the caffeine.", "2 unsweetened coffees in 7 days.")
        case "Late Night":
            ("Skip late-night food orders on 3 nights", "Eating late may affect sleep and next-morning blood sugar.", "3 nights without a late-night order in 7 days.")
        case "Groceries":
            ("Plan 3 home meals before shopping", "A short list keeps snacks and sugary extras out of the basket.", "3 planned home meals in 7 days.")
        case "Entertainment":
            ("Make 1 outing an active one", "A walk, hike or sport adds movement to time you already spend out.", "1 active outing in 7 days.")
        default:
            ("Skip one repeat purchase", "Skipping one repeat purchase is an easy first step.", "1 skipped repeat purchase in 7 days.")
        }
        return InsightAction(title: title, description: why, expectedOutcome: outcome, timeframe: "7 days", difficulty: 1)
    }

    static func whyItMatters(movement: Bool, targetMetric: String, foodCategory: String?) -> String {
        if movement { return "Regular movement may help support \(targetMetric)." }
        return "Fewer \(foodCategory ?? "takeout") purchases may help support \(targetMetric)."
    }

    static func fallbackPlan(context: InsightContext) -> InsightActionPlan {
        InsightActionPlan(
            movement: InsightPlanItem(
                title: "Walk or jog 25 minutes daily",
                recommendation: "Do a brisk walk or easy jog for 25 minutes on at least 5 days this week.",
                whyItMatters: whyItMatters(movement: true, targetMetric: context.targetMetric, foodCategory: nil),
                targetMetric: context.targetMetric, timeframe: "Next 7 days"),
            food: InsightPlanItem(
                title: "Replace two delivery meals",
                recommendation: "Swap two delivery, fast food, or late-night meals for home meals with lean protein and vegetables.",
                whyItMatters: whyItMatters(movement: false, targetMetric: context.targetMetric, foodCategory: context.findings.first?.category),
                targetMetric: context.targetMetric, timeframe: "Next 7 days"))
    }
}

// MARK: - Composition

nonisolated enum InsightComposer {

    /// The result and how many model fields the guardrail checked or replaced; nil when the
    /// answer has no usable model field at all (the caller retries).
    static func compose(_ answer: [String: Any], context: InsightContext, health: HealthReport)
        -> (result: InsightResult, audit: OutputGuardrail.Audit)? {
        var audit = OutputGuardrail.Audit(context: context.guardrail)
        let plan = answer["actionPlan"] as? [String: Any]
        let fallback = InsightTemplates.fallbackPlan(context: context)
        var modelFields = 0

        func planItem(_ key: String, fallback: InsightPlanItem) -> InsightPlanItem {
            let item = plan?[key] as? [String: Any]
            guard let title = text(item?["title"]), let recommendation = text(item?["recommendation"]) else { return fallback }
            modelFields += 1
            guard audit.passes([title], outcome: recommendation) else { return fallback }
            return InsightPlanItem(title: title, recommendation: recommendation, whyItMatters: fallback.whyItMatters,
                                   targetMetric: context.targetMetric, timeframe: "Next 7 days")
        }
        let actionPlan = InsightActionPlan(movement: planItem("movement", fallback: fallback.movement),
                                           food: planItem("food", fallback: fallback.food))

        let answered = answer["findings"] as? [[String: Any]] ?? []
        let findings = context.findings.enumerated().map { index, frame in
            let metricName = frame.metric?.name ?? frame.metricLabel
            var risk = InsightTemplates.risk(metricName: metricName)
            if index < answered.count, let written = text(answered[index]["risk"]) {
                modelFields += 1
                // A risk sentence about another category is a wrong link (phase 4 Mac run:
                // "sugary drinks" in the Food Delivery finding).
                let others = OutputGuardrail.categories(in: written, context: context.guardrail)
                    .filter { $0 != frame.category?.lowercased() }
                if audit.passes([written], offTopic: !others.isEmpty) { risk = written }
            }
            // Health facts come from the report, not from the model's wording.
            let healthDetail = frame.metric.map { metric in
                let range = metric.normalRange.isEmpty ? "" : " (reference \(metric.normalRange))"
                return "\(metric.name) \(metric.value)\(metric.unit.isEmpty ? "" : " \(metric.unit)") is \(metric.status.rawValue)\(range)."
            } ?? frame.metricLabel
            return InsightConnection(
                icon: frame.icon, cause: frame.cause,
                causeDetail: InsightTemplates.causeDetail(category: frame.category, monthly: frame.monthly),
                healthImpact: metricName, healthDetail: healthDetail, risk: risk, accentColor: frame.accentColor,
                actions: InsightTemplates.actions(category: frame.category, monthly: frame.monthly))
        }

        guard modelFields > 0 else { return nil }
        let result = InsightResult(keyFindings: findings, overallRiskScore: context.riskScore,
                                   monthlySpendingAtRisk: context.monthlyAtRisk, generatedAt: Date(), actionPlan: actionPlan)
        return (result, audit)
    }

    /// Non-empty trimmed text; a copied REPLACE template counts as missing.
    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("REPLACE") ? nil : trimmed
    }
}
