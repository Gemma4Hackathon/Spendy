import Foundation

final class OnDeviceHealthReportExtractor: HealthReportExtracting {

    var isModelReady: Bool { CactusManager.shared.isReady }

    // MARK: - HealthReportExtracting

    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        guard isModelReady else {
            throw CactusError.modelNotLoaded
        }
        return try await runVisionInference(imageData: imageData)
    }

    // MARK: - Vision Inference

    private func runVisionInference(imageData: Data) async throws -> HealthReport {
        let systemPrompt = """
        You are a medical data extraction assistant. \
        The image shows a health checkup or blood test report (possibly in Chinese or English). \
        Extract ALL health metrics you can identify. \
        Respond ONLY with a valid JSON array. No explanation, no markdown.
        """

        let userMessage = """
        For each metric provide:
        - name (in English)
        - value (numeric string)
        - unit (e.g. mg/dL, mmHg, %)
        - normalRange (e.g. < 100, 18.5–24, > 40)
        - status: "Normal", "Borderline", or "High"

        Example:
        [
          {"name":"Blood Pressure","value":"138/89","unit":"mmHg","normalRange":"< 120/80","status":"High"},
          {"name":"Fasting Glucose","value":"112","unit":"mg/dL","normalRange":"< 100","status":"High"}
        ]

        If you cannot read the image or find no metrics, return an empty array: []
        """

        let rawText = try await CactusManager.shared.visionComplete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            imageData: imageData,
            maxTokens: 800
        )

        return parseMetrics(from: rawText)
    }

    // MARK: - Parse JSON → HealthReport

    private func parseMetrics(from text: String) -> HealthReport {
        let cleaned = extractJSONArray(from: text)
        guard
            let data = cleaned.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else {
            return .demo
        }

        let metrics: [HealthMetric] = array.compactMap { dict in
            guard
                let name        = dict["name"],
                let value       = dict["value"],
                let unit        = dict["unit"],
                let normalRange = dict["normalRange"],
                let statusStr   = dict["status"]
            else { return nil }

            let status: HealthStatus = {
                switch statusStr.lowercased() {
                case "high", "warning": return .warning
                case "borderline":      return .borderline
                default:                return .normal
                }
            }()

            let progress: Double = {
                switch status {
                case .warning:    return Double.random(in: 0.75...0.95)
                case .borderline: return Double.random(in: 0.55...0.74)
                case .normal:     return Double.random(in: 0.30...0.54)
                }
            }()

            return HealthMetric(
                name:        name,
                value:       value,
                unit:        unit,
                normalRange: normalRange,
                status:      status,
                icon:        iconForMetric(name: name),
                progress:    progress
            )
        }

        if metrics.isEmpty { return .demo }

        return HealthReport(
            metrics:    metrics,
            reportDate: Date(),
            labName:    "Extracted by Gemma 4 (On-Device)"
        )
    }

    // MARK: - Helpers

    private func extractJSONArray(from text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = stripped.firstIndex(of: "["),
           let end   = stripped.lastIndex(of: "]") {
            return String(stripped[start...end])
        }
        return stripped
    }

    private func iconForMetric(name: String) -> String {
        let n = name.lowercased()
        if n.contains("pressure") || n.contains("bp")           { return "heart.fill" }
        if n.contains("glucose")  || n.contains("sugar")        { return "drop.fill" }
        if n.contains("hba1c")    || n.contains("hemoglobin")   { return "waveform.path.ecg" }
        if n.contains("ldl")      || n.contains("cholesterol")  { return "chart.line.uptrend.xyaxis" }
        if n.contains("hdl")                                     { return "shield.fill" }
        if n.contains("triglyceride")                            { return "flame.fill" }
        if n.contains("bmi")      || n.contains("weight")       { return "figure.stand" }
        if n.contains("uric")                                    { return "staroflife.fill" }
        return "waveform.path.ecg.rectangle"
    }
}
