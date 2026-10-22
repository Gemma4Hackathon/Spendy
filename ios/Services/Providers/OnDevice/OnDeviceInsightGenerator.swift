import Foundation

final class OnDeviceInsightGenerator: InsightGenerating {

    var isModelReady: Bool { CactusManager.shared.isReady }

    private func logSensitive(_ message: @autoclosure () -> String) {
        #if SPENDY_VERBOSE_LOGS
        print(message())
        #endif
    }

    // MARK: - InsightGenerating

    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        guard isModelReady else {
            print("[InsightGenerator] BLOCKED: CactusManager not ready (state: \(CactusManager.shared.state))")
            throw CactusError.modelNotLoaded
        }
        print("[InsightGenerator] Starting on-device inference...")
        let scope = PerfScope.begin("insight_generation")
        do {
            let result = try await runInference(profile: profile, spending: spending, health: health)
            scope.end("result=ok")
            return result
        } catch {
            scope.end("result=error")
            throw error
        }
    }

    // MARK: - Inference

    private func runInference(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        let context = InsightContext(spending: spending, health: health)
        let userMessage = buildUserMessage(profile: profile, spending: spending, health: health, context: context)

        do {
            let rawText = try await requestInsightJSON(userMessage: userMessage, isRetry: false)
            return try parseInsightResult(from: rawText, context: context, health: health)
        } catch {
            print("[InsightGenerator] First attempt failed: \(error.localizedDescription). Retrying with stricter schema.")
            let retryMessage = buildRetryUserMessage(from: userMessage)
            let rawText = try await requestInsightJSON(userMessage: retryMessage, isRetry: true)
            return try parseInsightResult(from: rawText, context: context, health: health)
        }
    }

    private func requestInsightJSON(userMessage: String, isRetry: Bool) async throws -> String {
        try await CactusManager.shared.complete(
            systemPrompt: insightSystemPrompt(isRetry: isRetry),
            userMessage: userMessage,
            maxTokens: 1000,
            temperature: 0
        )
    }

    private func insightSystemPrompt(isRetry: Bool) -> String {
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

    // MARK: - Context computed in Swift

    /// Everything the result needs that is not writing: scores, amounts, and which spending
    /// category and health metric each finding is about. Computed once, used for the prompt
    /// and the result, so the model never has to copy numbers back.
    private struct InsightContext {
        struct Finding {
            let icon: String
            let accentColor: String
            let cause: String
            let metric: HealthMetric?
            /// "Glucose: 115mg/dL", as the prompt names the metric.
            let metricLabel: String
        }

        let riskScore: Int
        let monthlyAtRisk: Double
        let findings: [Finding]
        /// Abnormal metric names for the action plan, e.g. "Glucose, Hemoglobin A1c".
        let targetMetric: String

        init(spending: [SpendingEntry], health: HealthReport) {
            let totalSpend = spending.reduce(0) { $0 + $1.amount }
            let abnormal = health.metrics.filter { $0.status != .normal }
            riskScore = min(95, 40 + abnormal.count * 12)
            monthlyAtRisk = Double(Int(totalSpend * 0.45))

            let topCats = SpendingCategory.allCases.compactMap { cat -> (String, Int)? in
                let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
                guard total > 0 else { return nil }
                return (cat.rawValue, Int(total))
            }.sorted { $0.1 > $1.1 }.prefix(2)
            let cat1 = topCats.first.map { "\($0.0) NT$\($0.1)" } ?? "Food Delivery NT$1500"
            let cat2 = topCats.dropFirst().first.map { "\($0.0) NT$\($0.1)" } ?? "Drinks NT$800"

            // Abnormal metrics first, so findings explain what the report flagged.
            let ranked = abnormal + health.metrics.filter { $0.status == .normal }
            let label: (HealthMetric?, String) -> String = { metric, fallback in
                metric.map { "\($0.name): \($0.value)\($0.unit)" } ?? fallback
            }
            findings = [
                Finding(icon: "fork.knife", accentColor: "amber", cause: "\(cat1) spending pattern",
                        metric: ranked.first, metricLabel: label(ranked.first, "Blood Sugar: 110 mg/dL")),
                Finding(icon: "moon.fill", accentColor: "red", cause: "\(cat2) spending pattern",
                        metric: ranked.dropFirst().first, metricLabel: label(ranked.dropFirst().first, "Blood Pressure: 130/85"))
            ]
            targetMetric = abnormal.isEmpty
                ? "Blood pressure, glucose, triglycerides"
                : abnormal.prefix(3).map(\.name).joined(separator: ", ")
        }
    }

    // MARK: - Prompt Builder

    private func buildUserMessage(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport,
        context: InsightContext
    ) -> String {
        let spendingLines = SpendingCategory.allCases.compactMap { cat -> String? in
            let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return "\(cat.rawValue) NT$\(Int(total))"
        }.joined(separator: ", ")

        let healthLines = health.metrics.map {
            "\($0.name) \($0.value)\($0.unit) (normal \($0.normalRange), status \($0.status.rawValue))"
        }.joined(separator: "; ")

        print("[InsightGenerator] Prompt data prepared (spendingChars=\(spendingLines.count), healthChars=\(healthLines.count)).")
        logSensitive("[InsightGenerator] Prompt data: spending=\(spendingLines.isEmpty ? "none" : spendingLines); health=\(healthLines.isEmpty ? "none" : healthLines)")

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
        Spending categories: \(spendingLines).
        Health metrics: \(healthLines).

        REQUIRED OUTPUT:
        Return one JSON object matching this schema exactly:
        {"actionPlan":{"movement":{"title":"REPLACE movement title","recommendation":"REPLACE with daily walking, jogging, or cycling duration","whyItMatters":"REPLACE with concise may help support language tied to \(context.targetMetric)"},"food":{"title":"REPLACE food title","recommendation":"REPLACE with specific delivery, fast food, sugar drink, or grocery swap target","whyItMatters":"REPLACE with concise helps reduce exposure language tied to \(context.targetMetric)"}},"findings":[\(finding(0)),\(finding(1))]}

        RULES:
        Replace every REPLACE value with a concrete sentence based on DATA.
        Every action title must start with a verb and include either a frequency, limit, or NT$ target.
        Every action description must connect the spending behavior to the health metric.
        Every expectedOutcome must be a patient-friendly 7-day outcome, not a diagnosis.
        Do not create generic example data.
        Do not include query_details or example_data.
        """
    }

    private func buildRetryUserMessage(from userMessage: String) -> String {
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

    // MARK: - Parse JSON → InsightResult

    private func parseInsightResult(from text: String, context: InsightContext, health: HealthReport) throws -> InsightResult {
        print("[InsightGenerator] Raw text received (\(text.count) chars).")
        logSensitive("[InsightGenerator] Raw text preview: \(text.prefix(200))")
        let parsed = LenientJSON.parse(text)
        PerfMonitor.logJSONParse(source: "insights", raw: text, result: parsed)
        print("[InsightGenerator] Extracted JSON candidate (\(parsed.candidate.count) chars).")
        logSensitive("[InsightGenerator] Extracted JSON preview: \(parsed.candidate.prefix(300))")

        guard let dict = parsed.dictionary else {
            print("[InsightGenerator] JSON parse failed")
            if parsed.object != nil {
                PerfMonitor.logParseFailure(source: "insights", reason: "not_object", raw: text, cleaned: parsed.candidate)
            }
            throw CactusError.inferenceFailure("Insight response was not valid JSON. Please regenerate.")
        }
        let cleaned = parsed.candidate
        // The prompt's schema is a template full of REPLACE markers; a copied template is not an answer.
        guard !cleaned.contains("REPLACE") else {
            print("[InsightGenerator] Response still contains REPLACE placeholders")
            PerfMonitor.logParseFailure(source: "insights", reason: "placeholders", raw: text, cleaned: cleaned)
            throw CactusError.inferenceFailure("Insight response repeated the template. Please regenerate.")
        }

        let findingsArray = dict["findings"] as? [[String: Any]] ?? []
        let actionPlan = parseActionPlan(dict["actionPlan"], targetMetric: context.targetMetric)
            ?? fallbackActionPlan(health: health)

        let findings: [InsightConnection] = zip(findingsArray, context.findings).compactMap { f, frame in
            guard
                let causeDetail = string(f["causeDetail"]),
                let risk        = string(f["risk"])
            else { return nil }

            // Health facts come from the report, not from the model's wording.
            let healthImpact = frame.metric?.name ?? frame.metricLabel
            let healthDetail = frame.metric.map { metric in
                let range = metric.normalRange.isEmpty ? "" : " (reference \(metric.normalRange))"
                return "\(metric.name) \(metric.value)\(metric.unit.isEmpty ? "" : " \(metric.unit)") is \(metric.status.rawValue)\(range)."
            } ?? frame.metricLabel

            let actionsArray = f["actions"] as? [[String: Any]] ?? []
            let actions: [InsightAction] = actionsArray.compactMap { a in
                guard
                    let title       = string(a["title"]),
                    let description = string(a["description"]),
                    let outcome     = string(a["expectedOutcome"])
                else { return nil }
                return InsightAction(
                    title:           title,
                    description:     description,
                    expectedOutcome: outcome,
                    timeframe:       "7 days",
                    difficulty:      2
                )
            }

            let displayActions = actions.isEmpty
                ? fallbackActions(cause: frame.cause, healthImpact: healthImpact)
                : Array(actions.prefix(3))

            return InsightConnection(
                icon:          frame.icon,
                cause:         frame.cause,
                causeDetail:   causeDetail,
                healthImpact:  healthImpact,
                healthDetail:  healthDetail,
                risk:          risk,
                accentColor:   frame.accentColor,
                actions:       displayActions
            )
        }

        guard !findings.isEmpty else {
            print("[InsightGenerator] JSON parse failed: no valid findings")
            PerfMonitor.logParseFailure(source: "insights", reason: "no_valid_findings", raw: text, cleaned: cleaned)
            throw CactusError.inferenceFailure("Insight response did not contain valid findings. Please regenerate.")
        }

        print("[InsightGenerator] Parsed \(findings.count) findings, riskScore=\(context.riskScore), monthlyAtRisk=\(Int(context.monthlyAtRisk))")

        return InsightResult(
            keyFindings:          findings,
            overallRiskScore:     context.riskScore,
            monthlySpendingAtRisk: context.monthlyAtRisk,
            generatedAt:          Date(),
            actionPlan:           actionPlan
        )
    }

    // MARK: - Helpers

    /// Non-empty trimmed text; numbers are accepted where the schema expects strings.
    private func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func fallbackActions(cause: String, healthImpact: String) -> [InsightAction] {
        [
            InsightAction(
                title: "Set a 7-day limit",
                description: "Use the \(cause) pattern as the first spending lever tied to \(healthImpact).",
                expectedOutcome: "Clearer weekly control without changing every habit at once.",
                timeframe: "7 days",
                difficulty: 1
            ),
            InsightAction(
                title: "Replace one repeat purchase",
                description: "Swapping one repeated purchase lowers exposure while keeping the plan realistic.",
                expectedOutcome: "One visible win to review in the next insight cycle.",
                timeframe: "7 days",
                difficulty: 2
            )
        ]
    }

    private func parseActionPlan(_ value: Any?, targetMetric: String) -> InsightActionPlan? {
        guard let dict = value as? [String: Any],
              let movement = parsePlanItem(dict["movement"], targetMetric: targetMetric),
              let food = parsePlanItem(dict["food"], targetMetric: targetMetric) else {
            return nil
        }
        return InsightActionPlan(movement: movement, food: food)
    }

    private func parsePlanItem(_ value: Any?, targetMetric: String) -> InsightPlanItem? {
        guard
            let dict = value as? [String: Any],
            let title = string(dict["title"]),
            let recommendation = string(dict["recommendation"]),
            let whyItMatters = string(dict["whyItMatters"])
        else { return nil }

        return InsightPlanItem(
            title: title,
            recommendation: recommendation,
            whyItMatters: whyItMatters,
            targetMetric: targetMetric,
            timeframe: "Next 7 days"
        )
    }

    private func fallbackActionPlan(health: HealthReport) -> InsightActionPlan {
        let abnormalMetrics = health.metrics
            .filter { $0.status != .normal }
            .prefix(3)
            .map(\.name)
        let target = abnormalMetrics.isEmpty
            ? "Blood pressure, glucose, triglycerides"
            : abnormalMetrics.joined(separator: ", ")

        return InsightActionPlan(
            movement: InsightPlanItem(
                title: "Walk or jog 25 minutes daily",
                recommendation: "Do a brisk walk or easy jog for 25 minutes on at least 5 days this week.",
                whyItMatters: "Consistent aerobic movement may help support blood pressure, glucose control, and triglyceride management.",
                targetMetric: target,
                timeframe: "Next 7 days"
            ),
            food: InsightPlanItem(
                title: "Replace two delivery meals",
                recommendation: "Swap two delivery, fast food, or late-night meals for grocery-based meals with lean protein and vegetables.",
                whyItMatters: "This helps reduce exposure to high-salt, fried, and sugary foods connected to the current marker pattern.",
                targetMetric: target,
                timeframe: "Next 7 days"
            )
        )
    }
}
