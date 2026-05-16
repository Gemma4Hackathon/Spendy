import Foundation

struct FinanceInsightItem: Identifiable, Hashable, Codable {
    var id = UUID()
    var icon: String
    var title: String
    var amount: String
    var impact: String
}

struct FinanceSummary: Codable {
    var totalSpent: Double
    var topCategory: SpendingCategory
    var riskCategories: [SpendingCategory]
    var aiMessage: String
    var categoryBreakdown: [SpendingCategory: Double]
    var shortTitle: String = "Spending health check"
    var quickTake: String = ""
    var primaryAction: String = ""
    var insightItems: [FinanceInsightItem] = []
}
