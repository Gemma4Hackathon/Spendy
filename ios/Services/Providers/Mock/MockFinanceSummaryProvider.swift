import Foundation

final class MockFinanceSummaryProvider: FinanceSummaryProviding {
    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary {
        try? await Task.sleep(nanoseconds: 900_000_000)

        var breakdown: [SpendingCategory: Double] = [:]
        entries.forEach { breakdown[$0.category, default: 0] += $0.amount }

        let total = entries.reduce(0) { $0 + $1.amount }
        let top = breakdown.max(by: { $0.value < $1.value })?.key ?? .other
        let beverage = (breakdown[.beverages] ?? 0) + (breakdown[.coffee] ?? 0)
        let deliveryNT = Int(breakdown[.foodDelivery] ?? 0)
        let beveragePct = total > 0 ? Int(beverage / total * 100) : 0

        let message = """
        [Spending Analysis – Last 30 Days]

        Your drink and delivery spending is worth noting. Sugary drinks and coffee together account for \(beveragePct)% of total spending, and delivery orders are concentrated during late-night hours.

        [High-Risk Categories]
        - Sugary Drinks  NT$\(Int(breakdown[.beverages] ?? 0)) — closely linked to elevated blood sugar
        - Food Delivery  NT$\(deliveryNT) — impacts metabolism and sleep quality
        - Late Night     NT$\(Int(breakdown[.lateNight] ?? 0)) — disrupts circadian rhythm

        [Recommendation] Keep your monthly drink budget under NT$500. Estimated savings: NT$\(Int((breakdown[.beverages] ?? 0) * 0.4))/month — and it may also help stabilize blood sugar.
        """

        return FinanceSummary(
            totalSpent: total,
            topCategory: top,
            riskCategories: [.beverages, .foodDelivery, .lateNight],
            aiMessage: message,
            categoryBreakdown: breakdown
        )
    }
}
