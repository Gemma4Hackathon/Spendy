import Foundation

final class OnDeviceFinanceSummaryProvider: FinanceSummaryProviding {

    var isModelReady: Bool { CactusManager.shared.isReady }

    // MARK: - FinanceSummaryProviding

    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary {
        var breakdown: [SpendingCategory: Double] = [:]
        entries.forEach { breakdown[$0.category, default: 0] += $0.amount }
        let total = entries.reduce(0) { $0 + $1.amount }
        let top = breakdown.max(by: { $0.value < $1.value })?.key ?? .other

        let riskCategories = detectRiskCategories(breakdown: breakdown, total: total)

        guard isModelReady else {
            return FinanceSummary(
                totalSpent: total,
                topCategory: top,
                riskCategories: riskCategories,
                aiMessage: "On-device model is still loading. Analysis will appear shortly.",
                categoryBreakdown: breakdown
            )
        }

        do {
            let insight = try await runInference(
                entries: entries,
                breakdown: breakdown,
                total: total
            )
            return FinanceSummary(
                totalSpent: total,
                topCategory: top,
                riskCategories: riskCategories,
                aiMessage: insight.aiMessage,
                categoryBreakdown: breakdown,
                shortTitle: insight.shortTitle,
                quickTake: insight.quickTake,
                primaryAction: insight.primaryAction,
                insightItems: insight.items
            )
        } catch {
            return FinanceSummary(
                totalSpent: total,
                topCategory: top,
                riskCategories: riskCategories,
                aiMessage: "On-device analysis failed: \(error.localizedDescription)",
                categoryBreakdown: breakdown
            )
        }
    }

    // MARK: - Inference

    private func runInference(
        entries: [SpendingEntry],
        breakdown: [SpendingCategory: Double],
        total: Double
    ) async throws -> FinanceInsightPayload {
        let lines = breakdown.sorted { $0.value > $1.value }
            .map { "- \($0.key.rawValue): NT$\(Int($0.value))" }
            .joined(separator: "\n")

        let recent = entries.prefix(5)
            .map { "- \($0.title): NT$\(Int($0.amount)) [\($0.category.rawValue)]" }
            .joined(separator: "\n")

        let systemPrompt = """
        You are a JSON generator for a finance health app. \
        Output ONLY one valid JSON object. No markdown. No explanation. \
        ABSOLUTELY NO emojis of any kind. \
        Keep every string short and specific.
        """

        let userMessage = """
        Total this month: NT$\(Int(total))

        Spending by category:
        \(lines)

        Recent transactions (latest 5):
        \(recent)

        Complete this JSON using real values from the data above:
        {"shortTitle":"maximum 6 words","quickTake":"one sentence, maximum 22 words","primaryAction":"one concrete action, maximum 16 words","items":[{"icon":"fork.knife","title":"category or behavior","amount":"NT$ amount","impact":"health or budget impact, maximum 14 words"},{"icon":"cup.and.saucer.fill","title":"category or behavior","amount":"NT$ amount","impact":"health or budget impact, maximum 14 words"},{"icon":"moon.fill","title":"category or behavior","amount":"NT$ amount","impact":"health or budget impact, maximum 14 words"}]}
        """

        let text = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 450,
            temperature: 0.2
        )
        return parseFinanceInsight(from: text, fallback: fallbackInsight(breakdown: breakdown, total: total))
    }

    // MARK: - Risk Detection

    private func detectRiskCategories(
        breakdown: [SpendingCategory: Double],
        total: Double
    ) -> [SpendingCategory] {
        guard total > 0 else { return [] }
        return breakdown
            .filter { $0.value / total > 0.15 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    private struct FinanceInsightPayload {
        var shortTitle: String
        var quickTake: String
        var primaryAction: String
        var items: [FinanceInsightItem]

        var aiMessage: String {
            """
            ## \(shortTitle)
            \(quickTake)

            - \(primaryAction)
            """
        }
    }

    private func parseFinanceInsight(
        from text: String,
        fallback: FinanceInsightPayload
    ) -> FinanceInsightPayload {
        let cleaned = extractJSONObject(from: text)
        guard
            let data = cleaned.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return fallback
        }

        let itemsArray = dict["items"] as? [[String: Any]] ?? []
        let items = itemsArray.compactMap { item -> FinanceInsightItem? in
            guard
                let title = item["title"] as? String,
                let amount = item["amount"] as? String,
                let impact = item["impact"] as? String
            else { return nil }
            return FinanceInsightItem(
                icon: item["icon"] as? String ?? "chart.bar.fill",
                title: title,
                amount: amount,
                impact: impact
            )
        }

        guard !items.isEmpty else { return fallback }

        return FinanceInsightPayload(
            shortTitle: dict["shortTitle"] as? String ?? fallback.shortTitle,
            quickTake: dict["quickTake"] as? String ?? fallback.quickTake,
            primaryAction: dict["primaryAction"] as? String ?? fallback.primaryAction,
            items: Array(items.prefix(3))
        )
    }

    private func fallbackInsight(
        breakdown: [SpendingCategory: Double],
        total: Double
    ) -> FinanceInsightPayload {
        let topItems = breakdown.sorted { $0.value > $1.value }.prefix(3).map { category, amount in
            FinanceInsightItem(
                icon: category.icon,
                title: category.rawValue,
                amount: "NT$\(Int(amount))",
                impact: "High share of monthly spending"
            )
        }
        let top = topItems.first?.title ?? "Spending"
        return FinanceInsightPayload(
            shortTitle: "Spending risk check",
            quickTake: "\(top) is the largest spending signal this month.",
            primaryAction: "Set a weekly cap for the top risk category.",
            items: topItems.isEmpty ? [
                FinanceInsightItem(icon: "chart.bar.fill", title: "Monthly spending", amount: "NT$\(Int(total))", impact: "Track before optimizing")
            ] : topItems
        )
    }

    private func extractJSONObject(from text: String) -> String {
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
