import Foundation

struct FinanceSummary {
    var totalSpent: Double
    var topCategory: SpendingCategory
    var riskCategories: [SpendingCategory]
    var aiMessage: String
    var categoryBreakdown: [SpendingCategory: Double]
}
