import Foundation

final class OnDeviceHealthReportExtractor: HealthReportExtracting {
    var isModelReady: Bool = false

    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        guard isModelReady else {
            throw ServiceError.modelNotReady
        }

        // Placeholder: run on-device OCR/extraction pipeline.
        throw ServiceError.notImplemented("On-device health extraction is not connected yet.")
    }
}
