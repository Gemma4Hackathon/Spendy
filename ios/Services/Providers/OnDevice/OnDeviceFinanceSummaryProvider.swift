import Foundation

final class OnDeviceFinanceSummaryProvider: FinanceSummaryProviding {
    var isModelReady: Bool = false

    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary {
        guard isModelReady else {
            return FinanceSummary(
                totalSpent: entries.reduce(0) { $0 + $1.amount },
                topCategory: .other,
                riskCategories: [],
                aiMessage: "On-device model is not ready. Falling back is recommended.",
                categoryBreakdown: [:]
            )
        }

        // Placeholder: run on-device model pipeline.
        return FinanceSummary(
            totalSpent: entries.reduce(0) { $0 + $1.amount },
            topCategory: .other,
            riskCategories: [],
            aiMessage: "On-device finance summary placeholder.",
            categoryBreakdown: [:]
        )
    }
}
