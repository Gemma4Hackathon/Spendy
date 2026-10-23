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

        let scope = PerfScope.begin("finance_summary", extra: "entries=\(entries.count)")
        do {
            let insight = try await runInference(
                entries: entries,
                breakdown: breakdown,
                total: total
            )
            scope.end("result=ok")
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
            scope.end("result=error")
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

        // Every number shown (amounts, weekly caps, the table) is computed in Swift; the model
        // only writes sentences. It miscalculated caps (NT$765/week for NT$800/month).
        let top = topCategories(breakdown).first
        let capHint = top.map { "keeps \($0.category.rawValue) under NT$\(SpendingTargets.weeklyCap($0.amount))/week" } ?? "sets a weekly NT$ cap"

        let systemPrompt = """
        You are a concise budget triage engine for a finance app. \
        The spending data is already provided in the user message. Never ask for more data. \
        Output ONLY one valid JSON object. No markdown. No explanation. \
        ABSOLUTELY NO emojis of any kind. \
        Keep every string short, practical, and based on NT$ amounts. \
        Write like Copilot Money or YNAB: calm, specific, and action-oriented. \
        Do not use vague urgency phrases like immediate attention, concerning, alarming, or high risk. \
        Do not invent health claims. \
        Never suggest cutting a category to zero; suggest a weekly cap or one swap instead.
        """

        let userMessage = """
        Total this month: NT$\(Int(total))

        Spending by category:
        \(lines)

        Recent transactions (latest 5):
        \(recent)

        Complete this JSON using only real values from the data above:
        {"shortTitle":"3-5 words, no alarm language","quickTake":"one concrete sentence with NT$ amount and percentage, maximum 20 words","primaryAction":"one 7-day action that \(capHint), maximum 16 words","note":"one short paragraph with concrete NT$ amounts, maximum 50 words","checklist":["one concrete 7-day step with a number","one concrete 7-day step with a number","one concrete 7-day step with a number"]}

        If uncertain, still return the JSON using the category totals. Do not say you need more information.
        """

        let text = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 500,
            temperature: 0
        )
        let guardrail = OutputGuardrail.Context(
            monthlyByCategory: Dictionary(uniqueKeysWithValues: breakdown.map { ($0.key.rawValue, Int($0.value)) }),
            extra: [Int(total)])
        return parseFinanceInsight(from: text, guardrail: guardrail, fallback: fallbackInsight(breakdown: breakdown, total: total))
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
        guardrail: OutputGuardrail.Context,
        fallback: FinanceInsightPayload
    ) -> FinanceInsightPayload {
        let parsed = LenientJSON.parse(text)
        PerfMonitor.logJSONParse(source: "finance", raw: text, result: parsed)
        let cleaned = parsed.candidate
        guard let dict = parsed.dictionary else {
            if parsed.object != nil {
                PerfMonitor.logParseFailure(source: "finance", reason: "not_object", raw: text, cleaned: cleaned)
            }
            return fallback
        }
        // The prompt's JSON is a template with instructions as values; a copied template is not an answer.
        let templateMarkers = ["maximum 16 words", "no alarm language", "maximum 20 words", "one concrete 7-day step"]
        guard !templateMarkers.contains(where: cleaned.contains) else {
            PerfMonitor.logParseFailure(source: "finance", reason: "placeholders", raw: text, cleaned: cleaned)
            return fallback
        }

        guard string(dict["quickTake"]) != nil || string(dict["note"]) != nil else {
            PerfMonitor.logParseFailure(source: "finance", reason: "no_text_fields", raw: text, cleaned: cleaned)
            return fallback
        }
        // Items and their caps are Swift-computed (see `fallbackInsight`).
        let items = fallback.items

        // Each sentence is checked; a wrong amount, zero target or monthly-as-weekly falls back
        // to the Swift-written field (see OutputGuardrail).
        var audit = OutputGuardrail.Audit(context: guardrail)
        func checked(_ key: String, fallback: String) -> String {
            guard let text = string(dict[key]) else { return fallback }
            return audit.passes([text]) ? text : fallback
        }
        let shortTitle = checked("shortTitle", fallback: fallback.shortTitle)
        let quickTake = checked("quickTake", fallback: fallback.quickTake)
        let primaryAction = checked("primaryAction", fallback: fallback.primaryAction)
        let markdownNote: String
        if let note = string(dict["note"]), audit.passes([note]) {
            let checklist = (dict["checklist"] as? [Any] ?? []).compactMap(string).prefix(3).filter { audit.passes([$0]) }
            markdownNote = Self.markdownNote(paragraph: note, items: items, checklist: Array(checklist))
        } else {
            markdownNote = fallback.markdownNote
        }
        PerfMonitor.log("guardrail", "source=finance \(audit.summary)")

        return FinanceInsightPayload(
            shortTitle: shortTitle,
            quickTake: quickTake,
            primaryAction: primaryAction,
            items: items,
            markdownNote: markdownNote
        )
    }

    /// The three largest categories, which the items and table describe.
    private func topCategories(_ breakdown: [SpendingCategory: Double]) -> [(category: SpendingCategory, amount: Double)] {
        breakdown.sorted { $0.value > $1.value }.prefix(3).map { (category: $0.key, amount: $0.value) }
    }

    /// The "Spendy AI notes" markdown: the model's paragraph, a table built from real amounts,
    /// and the model's 7-day checklist.
    private static func markdownNote(paragraph: String, items: [FinanceInsightItem], checklist: [String]) -> String {
        let rows = items.map { "| \($0.title) | \($0.amount) | \($0.impact) |" }.joined(separator: "\n")
        let steps = checklist.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(paragraph)

        | Focus | Current | Next move |
        | --- | ---: | --- |
        \(rows)
        \(steps.isEmpty ? "" : "\n**7-day checklist:**\n\(steps)")
        """
    }

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

    private func fallbackInsight(
        breakdown: [SpendingCategory: Double],
        total: Double
    ) -> FinanceInsightPayload {
        let topItems = breakdown.sorted { $0.value > $1.value }.prefix(3).map { category, amount in
            let weeklyTarget = SpendingTargets.weeklyCap(amount)
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
        let weeklyTarget = SpendingTargets.weeklyCap(topAmount)
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
}
