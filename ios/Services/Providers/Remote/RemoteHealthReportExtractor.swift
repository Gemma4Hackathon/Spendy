import Foundation

final class RemoteHealthReportExtractor: HealthReportExtracting {
    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        // Placeholder: wire to FastAPI /health/extract
        throw ServiceError.notImplemented("Remote health extraction is not connected yet.")
    }
}
