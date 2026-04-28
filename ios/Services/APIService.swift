import Foundation

// Legacy adapter kept to avoid hard breaks while migrating to
// FinanceSummaryProviding / HealthReportExtracting / InsightGenerating.
@available(*, deprecated, message: "Use feature-specific providers through AppEnvironment.router")
protocol APIServiceProtocol: FinanceSummaryProviding, HealthReportExtracting, InsightGenerating {}

@available(*, deprecated, message: "Use Mock* providers through ServiceRouter")
final class MockAPIService: APIServiceProtocol {
    private let finance = MockFinanceSummaryProvider()
    private let health = MockHealthReportExtractor()
    private let insight = MockInsightGenerator()

    func fetchFinanceSummary(entries: [SpendingEntry]) async -> FinanceSummary {
        await finance.fetchFinanceSummary(entries: entries)
    }

    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        try await health.extractHealthReport(imageData: imageData)
    }

    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        try await insight.generateInsights(profile: profile, spending: spending, health: health)
    }
}
