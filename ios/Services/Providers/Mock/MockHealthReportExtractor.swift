import Foundation

final class MockHealthReportExtractor: HealthReportExtracting {
    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        return .demo
    }
}
