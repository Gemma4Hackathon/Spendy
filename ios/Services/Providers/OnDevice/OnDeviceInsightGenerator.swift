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
            maxTokens: 400,
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

        guard let dict = parsed.dictionary else {
            print("[InsightGenerator] JSON parse failed")
            if parsed.object != nil {
                PerfMonitor.logParseFailure(source: "insights", reason: "not_object", raw: text, cleaned: parsed.candidate)
            }
            throw CactusError.inferenceFailure("Insight response was not valid JSON. Please regenerate.")
        }
        // Swift writes facts, amounts and actions; the model's plan and risk sentences are
        // checked by the guardrail and replaced by Swift text when they fail (InsightComposer).
        guard let (result, audit) = InsightComposer.compose(dict, context: context, health: health) else {
            print("[InsightGenerator] No usable plan or risk text in the answer")
            PerfMonitor.logParseFailure(source: "insights", reason: "no_model_fields", raw: text, cleaned: parsed.candidate)
            throw CactusError.inferenceFailure("Insight response did not contain a plan. Please regenerate.")
        }
        print("[InsightGenerator] Composed \(result.keyFindings.count) findings, riskScore=\(context.riskScore), monthlyAtRisk=\(Int(context.monthlyAtRisk))")
        PerfMonitor.log("guardrail", "source=insights \(audit.summary)")
        return result
    }
}
