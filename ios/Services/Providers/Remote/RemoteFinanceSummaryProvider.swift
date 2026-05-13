import Foundation

final class RemoteFinanceSummaryProvider: FinanceSummaryProviding {

    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary {
        var breakdown: [SpendingCategory: Double] = [:]
        entries.forEach { breakdown[$0.category, default: 0] += $0.amount }
        let total = entries.reduce(0) { $0 + $1.amount }
        let top = breakdown.max(by: { $0.value < $1.value })?.key ?? .other

        let prompt = buildPrompt(entries: entries, breakdown: breakdown, total: total)

        do {
            let text = try await GeminiAPI.textComplete(prompt: prompt)
            return FinanceSummary(
                totalSpent: total,
                topCategory: top,
                riskCategories: detectRiskCategories(breakdown: breakdown, total: total),
                aiMessage: text,
                categoryBreakdown: breakdown
            )
        } catch {
            // Graceful degradation to local mock message
            return FinanceSummary(
                totalSpent: total,
                topCategory: top,
                riskCategories: detectRiskCategories(breakdown: breakdown, total: total),
                aiMessage: "⚠️ AI analysis unavailable: \(error.localizedDescription)\n\nCheck your Gemini API key in Profile.",
                categoryBreakdown: breakdown
            )
        }
    }

    // MARK: - Prompt
    private func buildPrompt(entries: [SpendingEntry],
                              breakdown: [SpendingCategory: Double],
                              total: Double) -> String {
        let lines = breakdown.sorted { $0.value > $1.value }
            .map { "- \($0.key.rawValue): NT$\(Int($0.value))" }
            .joined(separator: "\n")

        return """
        You are a personal finance health advisor for a Taiwanese user.
        Analyze the following monthly spending data and provide concise, \
        actionable advice in 3–4 sentences. Focus on health-related spending risks \
        (sugary drinks, late-night delivery, caffeine). Be specific with NT$ amounts. \
        Reply in English.

        Total: NT$\(Int(total))
        Breakdown:
        \(lines)

        Recent entries (latest 5):
        \(entries.prefix(5).map { "- \($0.title): NT$\(Int($0.amount)) [\($0.category.rawValue)]" }.joined(separator: "\n"))

        Provide your finance + health risk analysis:
        """
    }

    // MARK: - Risk detection
    private func detectRiskCategories(breakdown: [SpendingCategory: Double],
                                       total: Double) -> [SpendingCategory] {
        guard total > 0 else { return [] }
        return breakdown
            .filter { $0.value / total > 0.15 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
}
