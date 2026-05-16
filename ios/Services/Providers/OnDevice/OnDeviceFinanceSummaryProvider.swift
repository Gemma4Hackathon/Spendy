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
            .map { category, amount in
                let share = total > 0 ? Int((amount / total) * 100) : 0
                return "- \(category.rawValue): NT$\(Int(amount)) (\(share)% of tracked spend)"
            }
            .joined(separator: "\n")

        let recent = entries.prefix(5)
            .map { "- \($0.title): NT$\(Int($0.amount)) [\($0.category.rawValue)]" }
            .joined(separator: "\n")

        let systemPrompt = """
        You are a concise budget triage engine for a finance app. \
        The spending data is already provided in the user message. Never ask for more data. \
        Output ONLY one valid JSON object. No markdown. No explanation. \
        ABSOLUTELY NO emojis of any kind. \
        Keep every string short, practical, and based on NT$ amounts. \
        Write like Copilot Money or YNAB: calm, specific, and action-oriented. \
        Do not use vague urgency phrases like immediate attention, concerning, alarming, or high risk. \
        Do not invent health claims.
        """

        let userMessage = """
        Total this month: NT$\(Int(total))

        Spending by category:
        \(lines)

        Recent transactions (latest 5):
        \(recent)

        Complete this JSON using only real values from the data above:
        {"shortTitle":"3-5 words, no alarm language","quickTake":"one concrete sentence with NT$ amount and percentage, maximum 20 words","primaryAction":"one measurable 7-day action with NT$ target, maximum 16 words","items":[{"icon":"fork.knife","title":"category or behavior","amount":"NT$ amount","impact":"specific budget lever, maximum 10 words"},{"icon":"cup.and.saucer.fill","title":"category or behavior","amount":"NT$ amount","impact":"specific budget lever, maximum 10 words"},{"icon":"moon.fill","title":"category or behavior","amount":"NT$ amount","impact":"specific budget lever, maximum 10 words"}],"markdownNote":"Markdown only. Include one short paragraph, a 3-row table, and one 7-day checklist. Use concrete NT$ amounts. Maximum 120 words."}

        If uncertain, still return the JSON using the category totals. Do not say you need more information.
        """

        let text = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 650,
            temperature: 0.05
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
        var markdownNote: String

        var aiMessage: String {
            let trimmedNote = markdownNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNote.isEmpty {
                return trimmedNote
            }

            let rows = items.map { item in
                "| \(item.title) | \(item.amount) | \(item.impact) |"
            }.joined(separator: "\n")

            return """
            ## \(shortTitle)

            \(quickTake)

            | Budget lever | Current | Next move |
            | --- | ---: | --- |
            \(rows)

            **7-day action:** \(primaryAction)
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
            items: Array(items.prefix(3)),
            markdownNote: dict["markdownNote"] as? String ?? fallback.markdownNote
        )
    }

    private func fallbackInsight(
        breakdown: [SpendingCategory: Double],
        total: Double
    ) -> FinanceInsightPayload {
        let topItems = breakdown.sorted { $0.value > $1.value }.prefix(3).map { category, amount in
            let weeklyTarget = max(100, Int(amount * 0.75 / 4))
            let monthlyTrim = max(100, Int(amount * 0.20))
            return FinanceInsightItem(
                icon: category.icon,
                title: category.rawValue,
                amount: "NT$\(Int(amount))",
                impact: "Trim NT$\(monthlyTrim), cap NT$\(weeklyTarget)/week"
            )
        }
        let sorted = breakdown.sorted { $0.value > $1.value }
        let topCategory = sorted.first?.key.rawValue ?? "Spending"
        let topAmount = sorted.first?.value ?? total
        let topShare = total > 0 ? Int((topAmount / total) * 100) : 0
        let weeklyTarget = max(100, Int(topAmount * 0.75 / 4))
        return FinanceInsightPayload(
            shortTitle: "Spending focus this week",
            quickTake: "\(topCategory) leads tracked spending at NT$\(Int(topAmount)), about \(topShare)% of this month.",
            primaryAction: "Keep \(topCategory) under NT$\(weeklyTarget) for the next 7 days.",
            items: topItems.isEmpty ? [
                FinanceInsightItem(icon: "chart.bar.fill", title: "Monthly spending", amount: "NT$\(Int(total))", impact: "Track before optimizing")
            ] : topItems,
            markdownNote: fallbackMarkdownNote(
                topCategory: topCategory,
                topAmount: topAmount,
                topShare: topShare,
                weeklyTarget: weeklyTarget,
                items: topItems
            )
        )
    }

    private func fallbackMarkdownNote(
        topCategory: String,
        topAmount: Double,
        topShare: Int,
        weeklyTarget: Int,
        items: [FinanceInsightItem]
    ) -> String {
        let tableRows = items.prefix(3).map { item in
            "| \(item.title) | \(item.amount) | \(item.impact) |"
        }.joined(separator: "\n")
        let rows = tableRows.isEmpty
            ? "| \(topCategory) | NT$\(Int(topAmount)) | Set a weekly cap |"
            : tableRows

        return """
        ## AI budget note

        \(topCategory) is the clearest lever this week at NT$\(Int(topAmount)), about \(topShare)% of tracked spending. Use a small cap instead of cutting everything at once.

        | Focus | Current | Next move |
        | --- | ---: | --- |
        \(rows)

        **7-day checklist:** keep \(topCategory) under NT$\(weeklyTarget), skip one repeat purchase, and review the result next week.
        """
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
