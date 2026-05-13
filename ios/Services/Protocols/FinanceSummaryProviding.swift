import Foundation

protocol FinanceSummaryProviding {
    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary
}
