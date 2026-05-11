import Foundation

final class RemoteInsightGenerator: InsightGenerating {

    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {

        let prompt = buildPrompt(profile: profile, spending: spending, health: health)
        let rawText = try await GeminiAPI.textComplete(prompt: prompt)
        return parseInsightResult(from: rawText, spending: spending)
    }

    // MARK: - Prompt
    private func buildPrompt(profile: UserProfile,
                              spending: [SpendingEntry],
                              health: HealthReport) -> String {
        let spendingLines = SpendingCategory.allCases.compactMap { cat -> String? in
            let total = spending.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return "  \(cat.rawValue): NT$\(Int(total))"
        }.joined(separator: "\n")

        let healthLines = health.metrics.map {
            "  \($0.name): \($0.value) \($0.unit) [\($0.status.rawValue)] (normal: \($0.normalRange))"
        }.joined(separator: "\n")

        return """
        You are Spendy Intelligence, an AI that finds connections between spending habits \
        and health metrics.

        User: \(profile.name), age \(profile.age), \(profile.gender), BMI \(String(format:"%.1f", profile.bmi))
        Goals: \(profile.goals.joined(separator: ", "))

        Monthly Spending:
        \(spendingLines)

        Health Metrics:
        \(healthLines)

        Identify 2–3 concrete connections between spending patterns and health markers. \
        For each connection, respond with EXACTLY this JSON format and nothing else:
        {
          "riskScore": <0-100 integer>,
          "monthlyAtRisk": <NT$ amount as number>,
          "findings": [
            {
              "icon": "<SF Symbol name>",
              "cause": "<spending habit title>",
              "causeDetail": "<1 sentence with NT$ amount and frequency>",
              "healthImpact": "<health metric name>",
              "healthDetail": "<current value and what it means>",
              "risk": "<1 sentence long-term risk if habit continues>",
              "accentColor": "<red|amber|blue>",
              "actions": [
                {
                  "title": "<short action>",
                  "description": "<why it helps>",
                  "expectedOutcome": "<measurable result>",
                  "timeframe": "<e.g. 3 months>",
                  "difficulty": <1-3>
                }
              ]
            }
          ]
        }

        Reply with ONLY the JSON. No markdown, no explanation.
        """
    }

    // MARK: - Parse JSON → InsightResult
    private func parseInsightResult(from text: String, spending: [SpendingEntry]) -> InsightResult {
        let cleaned = extractJSON(from: text)
        guard let data = cleaned.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return InsightResult.demo  // fallback
        }

        let riskScore = dict["riskScore"] as? Int ?? 65
        let monthlyAtRisk = dict["monthlyAtRisk"] as? Double ?? Double(spending.reduce(0) { $0 + $1.amount } / 2)
        let findingsArray = dict["findings"] as? [[String: Any]] ?? []

        let findings: [InsightConnection] = findingsArray.compactMap { f in
            guard let cause = f["cause"] as? String,
                  let causeDetail = f["causeDetail"] as? String,
                  let healthImpact = f["healthImpact"] as? String,
                  let healthDetail = f["healthDetail"] as? String,
                  let risk = f["risk"] as? String,
                  let accentColor = f["accentColor"] as? String else { return nil }

            let icon = f["icon"] as? String ?? "sparkles"
            let actionsArray = f["actions"] as? [[String: Any]] ?? []
            let actions: [InsightAction] = actionsArray.compactMap { a in
                guard let title = a["title"] as? String,
                      let description = a["description"] as? String,
                      let outcome = a["expectedOutcome"] as? String,
                      let timeframe = a["timeframe"] as? String else { return nil }
                let difficulty = a["difficulty"] as? Int ?? 2
                return InsightAction(
                    title: title,
                    description: description,
                    expectedOutcome: outcome,
                    timeframe: timeframe,
                    difficulty: difficulty
                )
            }

            return InsightConnection(
                icon: icon,
                cause: cause,
                causeDetail: causeDetail,
                healthImpact: healthImpact,
                healthDetail: healthDetail,
                risk: risk,
                accentColor: accentColor,
                actions: actions
            )
        }

        return InsightResult(
            keyFindings: findings.isEmpty ? InsightResult.demo.keyFindings : findings,
            overallRiskScore: riskScore,
            monthlySpendingAtRisk: monthlyAtRisk,
            generatedAt: Date()
        )
    }

    private func extractJSON(from text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = stripped.firstIndex(of: "{"),
           let end = stripped.lastIndex(of: "}") {
            return String(stripped[start...end])
        }
        return stripped
    }
}
