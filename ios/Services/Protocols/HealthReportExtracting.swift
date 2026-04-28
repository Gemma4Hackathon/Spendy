import Foundation

protocol HealthReportExtracting {
    func extractHealthReport(imageData: Data) async throws -> HealthReport
}
