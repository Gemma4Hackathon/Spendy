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
        try await generateInsights(profile: profile, spending: spending, health: health, onProgress: { _ in })
    }

    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport,
        onProgress: @escaping @Sendable (InsightProgress) -> Void
    ) async throws -> InsightResult {
        guard isModelReady else {
            print("[InsightGenerator] BLOCKED: CactusManager not ready (state: \(CactusManager.shared.state))")
            throw CactusError.modelNotLoaded
        }
        print("[InsightGenerator] Starting on-device inference...")
        let scope = PerfScope.begin("insight_generation")
        do {
            let result = try await runInference(profile: profile, spending: spending, health: health, onProgress: onProgress)
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
        health: HealthReport,
        onProgress: @escaping @Sendable (InsightProgress) -> Void
    ) async throws -> InsightResult {
        let context = InsightContext(spending: spending, health: health)
        let userMessage = InsightPrompt.user(profile: profile, spending: spending, health: health, context: context)
        print("[InsightGenerator] Prompt data prepared (spendingChars=\(InsightPrompt.spendingLines(spending).count), healthChars=\(InsightPrompt.healthLines(health).count)).")
        logSensitive("[InsightGenerator] Prompt data: spending=\(InsightPrompt.spendingLines(spending)); health=\(InsightPrompt.healthLines(health))")

        do {
            let rawText = try await requestInsightJSON(userMessage: userMessage, isRetry: false, onProgress: onProgress)
            return try parseInsightResult(from: rawText, context: context, health: health)
        } catch {
            print("[InsightGenerator] First attempt failed: \(error.localizedDescription). Retrying with stricter schema.")
            let retryMessage = InsightPrompt.retry(userMessage)
            let rawText = try await requestInsightJSON(userMessage: retryMessage, isRetry: true, onProgress: onProgress)
            return try parseInsightResult(from: rawText, context: context, health: health)
        }
    }

    private func requestInsightJSON(
        userMessage: String,
        isRetry: Bool,
        onProgress: @escaping @Sendable (InsightProgress) -> Void
    ) async throws -> String {
        let stream = ProgressStream(report: onProgress)
        let text = try await CactusManager.shared.complete(
            systemPrompt: InsightPrompt.system(isRetry: isRetry),
            userMessage: userMessage,
            maxTokens: 1000,
            temperature: 0,
            onToken: { stream.append($0) }
        )
        onProgress(InsightProgress.from(partial: text, tokens: stream.tokenCount))
        return text
    }

    /// Collects streamed tokens on the inference queue and reports parsed progress every
    /// 8 tokens (parsing a 2 KB partial answer takes well under a millisecond).
    private nonisolated final class ProgressStream: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        private var tokens = 0
        private let report: @Sendable (InsightProgress) -> Void

        init(report: @escaping @Sendable (InsightProgress) -> Void) { self.report = report }

        var tokenCount: Int { lock.withLock { tokens } }

        func append(_ token: String) {
            let snapshot: (String, Int)? = lock.withLock {
                text += token
                tokens += 1
                return tokens % 8 == 0 ? (text, tokens) : nil
            }
            if let (partial, count) = snapshot {
                report(InsightProgress.from(partial: partial, tokens: count))
            }
        }
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
        // Every sentence is checked before it is shown; a field that names a wrong amount, a
        // zero target, a monthly total as weekly or a lab-value promise gets Swift-written text.
        var audit = OutputGuardrail.Audit(context: context.guardrail)
        let fallbackPlan = fallbackActionPlan(health: health)
        var actionPlan = parseActionPlan(dict["actionPlan"], targetMetric: context.targetMetric) ?? fallbackPlan
        if !audit.passes([actionPlan.movement.title, actionPlan.movement.recommendation, actionPlan.movement.whyItMatters]) {
            actionPlan.movement = fallbackPlan.movement
        }
        if !audit.passes([actionPlan.food.title, actionPlan.food.recommendation, actionPlan.food.whyItMatters]) {
            actionPlan.food = fallbackPlan.food
        }

        let findings: [InsightConnection] = zip(findingsArray, context.findings).compactMap { f, frame in
            guard
                var causeDetail = string(f["causeDetail"]),
                var risk        = string(f["risk"])
            else { return nil }
            if !audit.passes([causeDetail]) { causeDetail = frame.safeCauseDetail }
            if !audit.passes([risk]) { risk = frame.safeRisk }

            // Health facts come from the report, not from the model's wording.
            let healthImpact = frame.metric?.name ?? frame.metricLabel
            let healthDetail = frame.metric.map { metric in
                let range = metric.normalRange.isEmpty ? "" : " (reference \(metric.normalRange))"
                return "\(metric.name) \(metric.value)\(metric.unit.isEmpty ? "" : " \(metric.unit)") is \(metric.status.rawValue)\(range)."
            } ?? frame.metricLabel

            let actionsArray = f["actions"] as? [[String: Any]] ?? []
            let actions: [InsightAction] = actionsArray.enumerated().compactMap { index, a in
                guard
                    let title       = string(a["title"]),
                    let description = string(a["description"]),
                    let outcome     = string(a["expectedOutcome"])
                else { return nil }
                guard audit.passes([title, description], outcome: outcome) else { return frame.safeAction(index) }
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
        PerfMonitor.log("guardrail", "source=insights \(audit.summary)")

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
