import Foundation

final class MockInsightGenerator: InsightGenerating {
    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        return .demo
    }
}
