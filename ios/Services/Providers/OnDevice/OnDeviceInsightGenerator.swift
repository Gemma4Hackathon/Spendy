import Foundation

final class OnDeviceInsightGenerator: InsightGenerating {
    var isModelReady: Bool = false

    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult {
        guard isModelReady else {
            throw ServiceError.modelNotReady
        }

        // Placeholder: run on-device reasoning pipeline.
        throw ServiceError.notImplemented("On-device insight generation is not connected yet.")
    }
}
