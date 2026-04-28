import Foundation

final class RemoteFinanceSummaryProvider: FinanceSummaryProviding {
    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary {
        // Placeholder: wire to FastAPI /spending/summary
        return FinanceSummary(
            totalSpent: entries.reduce(0) { $0 + $1.amount },
            topCategory: .other,
            riskCategories: [],
            aiMessage: "Remote finance summary is not connected yet.",
            categoryBreakdown: [:]
        )
    }
}
