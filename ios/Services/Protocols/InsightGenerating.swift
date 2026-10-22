import Foundation

protocol InsightGenerating {
    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport
    ) async throws -> InsightResult

    /// Same, reporting what the model has written so far (called off the main thread).
    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport,
        onProgress: @escaping @Sendable (InsightProgress) -> Void
    ) async throws -> InsightResult
}

extension InsightGenerating {
    /// Providers that cannot stream report no progress.
    func generateInsights(
        profile: UserProfile,
        spending: [SpendingEntry],
        health: HealthReport,
        onProgress: @escaping @Sendable (InsightProgress) -> Void
    ) async throws -> InsightResult {
        try await generateInsights(profile: profile, spending: spending, health: health)
    }
}
