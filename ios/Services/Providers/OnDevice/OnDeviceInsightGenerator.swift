import Foundation

final class OnDeviceInsightGenerator: InsightGenerating {

    var isModelReady: Bool { CactusManager.shared.isReady }

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
        return try await runInference(profile: profile, spending: spending, health: health)
    }

    // MARK: - Inference

    private func runInference(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        let userMessage = buildUserMessage(profile: profile, spending: spending, health: health)

        do {
            let rawText = try await requestInsightJSON(userMessage: userMessage, isRetry: false)
            return try parseInsightResult(from: rawText, spending: spending)
        } catch {
            print("[InsightGenerator] First attempt failed: \(error.localizedDescription). Retrying with stricter schema.")
            let retryMessage = buildRetryUserMessage(from: userMessage)
            let rawText = try await requestInsightJSON(userMessage: retryMessage, isRetry: true)
            return try parseInsightResult(from: rawText, spending: spending)
        }
    }

    private func requestInsightJSON(userMessage: String, isRetry: Bool) async throws -> String {
        try await CactusManager.shared.complete(
            systemPrompt: insightSystemPrompt(isRetry: isRetry),
            userMessage: userMessage,
            maxTokens: 1400,
            temperature: isRetry ? 0.05 : 0.1
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
        Required top-level keys exactly: riskScore, monthlyAtRisk, findings.
        The findings array MUST contain 2 objects.
        Do not output query_details, example_data, schema descriptions, markdown, comments, or text outside JSON.
        Do not use placeholders such as REPLACE.
        Do not use emojis.
        Use only the supplied Spending and Health values.
        """
    }

    // MARK: - Prompt Builder

    private func buildUserMessage(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) -> String {
        let spendingLines = SpendingCategory.allCases.compactMap { cat -> String? in
            let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return "\(cat.rawValue) NT$\(Int(total))"
        }.joined(separator: ", ")

        let healthLines = health.metrics.map {
            "\($0.name) \($0.value)\($0.unit) (normal \($0.normalRange), status \($0.status.rawValue))"
        }.joined(separator: "; ")

        let totalSpend = spending.reduce(0) { $0 + $1.amount }
        let atRiskEstimate = Int(totalSpend * 0.45)
        let abnormalCount = health.metrics.filter { $0.status != .normal }.count
        let suggestedRisk = min(95, 40 + abnormalCount * 12)

        let topCats = SpendingCategory.allCases.compactMap { cat -> (String, Int)? in
            let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return (cat.rawValue, Int(total))
        }.sorted { $0.1 > $1.1 }.prefix(2)

        let cat1 = topCats.first.map { "\($0.0) NT$\($0.1)" } ?? "Food Delivery NT$1500"
        let cat2 = topCats.dropFirst().first.map { "\($0.0) NT$\($0.1)" } ?? "Drinks NT$800"
        let health1 = health.metrics.first.map { "\($0.name): \($0.value)\($0.unit)" } ?? "Blood Sugar: 110 mg/dL"
        let health2 = health.metrics.dropFirst().first.map { "\($0.name): \($0.value)\($0.unit)" } ?? "Blood Pressure: 130/85"

        print("[InsightGenerator] Prompt data: spending=\(spendingLines.isEmpty ? "none" : spendingLines); health=\(healthLines.isEmpty ? "none" : healthLines)")

        return """
        TASK:
        Generate health-and-spending risk insights using the data below.

        DATA:
        User: \(profile.age)yo \(profile.gender), BMI \(String(format: "%.1f", profile.bmi)).
        Spending categories: \(spendingLines).
        Health metrics: \(healthLines).

        REQUIRED OUTPUT:
        Return one JSON object matching this schema exactly:
        {"riskScore":\(suggestedRisk),"monthlyAtRisk":\(atRiskEstimate),"findings":[{"icon":"fork.knife","cause":"\(cat1) spending pattern","causeDetail":"REPLACE with 1 sentence about \(cat1) and health risk","healthImpact":"REPLACE with metric name","healthDetail":"REPLACE using \(health1)","risk":"REPLACE with 1 sentence consequence","accentColor":"amber","actions":[{"title":"REPLACE with short action","description":"REPLACE why","expectedOutcome":"REPLACE result","timeframe":"REPLACE time","difficulty":2}]},{"icon":"moon.fill","cause":"\(cat2) spending pattern","causeDetail":"REPLACE with 1 sentence about \(cat2) and health risk","healthImpact":"REPLACE with metric name","healthDetail":"REPLACE using \(health2)","risk":"REPLACE with 1 sentence consequence","accentColor":"red","actions":[{"title":"REPLACE with short action","description":"REPLACE why","expectedOutcome":"REPLACE result","timeframe":"REPLACE time","difficulty":2}]}]}

        RULES:
        Replace every REPLACE value with a concrete sentence based on DATA.
        Do not create generic example data.
        Do not include query_details or example_data.
        """
    }

    private func buildRetryUserMessage(from userMessage: String) -> String {
        """
        \(userMessage)

        RETRY CONSTRAINTS:
        Your previous response was invalid because it did not contain top-level riskScore, monthlyAtRisk, and findings.
        Output only the required JSON object now.
        The first character must be {.
        The top-level object must contain a non-empty findings array with exactly 2 findings.
        """
    }

    // MARK: - Parse JSON → InsightResult

    private func parseInsightResult(from text: String, spending: [SpendingEntry]) throws -> InsightResult {
        print("[InsightGenerator] Raw text (\(text.count) chars): \(text.prefix(200))")
        let cleaned = extractJSONObject(from: text)
        print("[InsightGenerator] Extracted JSON (\(cleaned.count) chars): \(cleaned.prefix(300))")

        guard
            let data = cleaned.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[InsightGenerator] JSON parse failed")
            throw CactusError.inferenceFailure("Insight response was not valid JSON. Please regenerate.")
        }

        let riskScore = parseInt(dict["riskScore"]) ?? 65
        let monthlyAtRisk = parseDouble(dict["monthlyAtRisk"])
            ?? Double(spending.reduce(0) { $0 + $1.amount } / 2)
        let findingsArray  = dict["findings"]       as? [[String: Any]] ?? []

        let findings: [InsightConnection] = findingsArray.compactMap { f in
            guard
                let cause         = f["cause"]         as? String,
                let causeDetail   = f["causeDetail"]   as? String,
                let healthImpact  = f["healthImpact"]  as? String,
                let healthDetail  = f["healthDetail"]  as? String,
                let risk          = f["risk"]           as? String,
                let accentColor   = f["accentColor"]   as? String
            else { return nil }

            let icon         = f["icon"]    as? String ?? "sparkles"
            let actionsArray = f["actions"] as? [[String: Any]] ?? []

            let actions: [InsightAction] = actionsArray.compactMap { a in
                guard
                    let title       = a["title"]           as? String,
                    let description = a["description"]     as? String,
                    let outcome     = a["expectedOutcome"] as? String,
                    let timeframe   = a["timeframe"]       as? String
                else { return nil }
                return InsightAction(
                    title:           title,
                    description:     description,
                    expectedOutcome: outcome,
                    timeframe:       timeframe,
                    difficulty:      a["difficulty"] as? Int ?? 2
                )
            }

            return InsightConnection(
                icon:          icon,
                cause:         cause,
                causeDetail:   causeDetail,
                healthImpact:  healthImpact,
                healthDetail:  healthDetail,
                risk:          risk,
                accentColor:   accentColor,
                actions:       actions
            )
        }

        guard !findings.isEmpty else {
            print("[InsightGenerator] JSON parse failed: no valid findings")
            throw CactusError.inferenceFailure("Insight response did not contain valid findings. Please regenerate.")
        }

        print("[InsightGenerator] Parsed \(findings.count) findings, riskScore=\(riskScore), monthlyAtRisk=\(Int(monthlyAtRisk))")

        return InsightResult(
            keyFindings:          findings,
            overallRiskScore:     riskScore,
            monthlySpendingAtRisk: monthlyAtRisk,
            generatedAt:          Date()
        )
    }

    // MARK: - Helpers

    private func extractJSONObject(from text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = stripped.firstIndex(of: "{"),
           let end   = stripped.lastIndex(of: "}") {
            return String(stripped[start...end])
        }
        return stripped
    }

    private func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let intValue = value as? Int { return Double(intValue) }
        if let stringValue = value as? String { return Double(stringValue) }
        return nil
    }
}
