import Foundation

/// Where a scan is, so the UI can show the real pipeline instead of a timer.
enum HealthScanStage: Sendable {
    case readingText      // Apple Vision OCR
    case structuring      // Gemma 4 structures what the table reader did not cover
    case visionFallback   // Gemma 4 vision, only when OCR found too little
    case verifying        // values and flags checked against the report
}

/// Scan failures with messages meant for the user.
enum HealthScanError: LocalizedError {
    case unreadable
    case noText
    case noMetrics

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The report text could not be read. Try a sharper, well-lit photo of the full page."
        case .noText:
            return "No text was found in this image. Choose a photo of a lab report."
        case .noMetrics:
            return "Text was found, but no lab results could be read from it. Make sure the results table is visible."
        }
    }
}

protocol HealthReportExtracting {
    func extractHealthReport(imageData: Data) async throws -> HealthReport

    /// Same, reporting each stage as it starts.
    func extractHealthReport(imageData: Data, onStage: @escaping @MainActor (HealthScanStage) -> Void) async throws -> HealthReport
}

extension HealthReportExtracting {
    /// Providers without stages report none.
    func extractHealthReport(imageData: Data, onStage: @escaping @MainActor (HealthScanStage) -> Void) async throws -> HealthReport {
        try await extractHealthReport(imageData: imageData)
    }
}
