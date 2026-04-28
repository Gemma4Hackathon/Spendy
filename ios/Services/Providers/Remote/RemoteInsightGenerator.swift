import Foundation

final class RemoteInsightGenerator: InsightGenerating {
    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        // Placeholder: wire to FastAPI /insights/final
        throw ServiceError.notImplemented("Remote insight generation is not connected yet.")
    }
}
