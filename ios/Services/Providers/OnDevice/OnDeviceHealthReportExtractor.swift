import Foundation
import UIKit
import Vision

final class OnDeviceHealthReportExtractor: HealthReportExtracting {

    var isModelReady: Bool { CactusManager.shared.isReady }

    // MARK: - HealthReportExtracting

    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        if isModelReady {
            do {
                print("[HealthExtractor] Trying Gemma 4 vision extraction...")
                return try await runVisionInference(imageData: imageData)
            } catch {
                print("[HealthExtractor] Gemma 4 vision failed, falling back to Apple Vision OCR: \(error.localizedDescription)")
            }
        }

        let text = try await recognizeText(from: imageData)
        print("[HealthExtractor] OCR text (\(text.count) chars): \(text.prefix(300))")

        if let report = parseReportFromOCR(text) {
            return report
        }

        guard isModelReady else {
            throw CactusError.modelNotLoaded
        }
        return try await runTextInference(ocrText: text)
    }

    // MARK: - OCR

    private func recognizeText(from imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage
        else {
            throw CactusError.inferenceFailure("The selected image could not be decoded.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n")
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(throwing: CactusError.inferenceFailure("No text was recognized in the selected image."))
                    } else {
                        continuation.resume(returning: text)
                    }
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US", "zh-Hant", "zh-Hans"]

                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Vision / Text Inference

    private func runVisionInference(imageData: Data) async throws -> HealthReport {
        let systemPrompt = """
        You are a medical data extraction assistant. \
        The user image is a health checkup or blood test report. \
        Read the visible table values directly from the image. \
        Respond ONLY with one valid JSON object. No explanation, no markdown.
        """

        let userMessage = """
        Extract all visible health metrics from this report image.

        Return this exact JSON structure:
        {
          "metrics": [
            {"name":"Blood Pressure","value":"138/89","unit":"mmHg","normalRange":"< 120/80","status":"High"}
          ],
          "evidenceTrace": [
            "Blood Pressure 138/89 mmHg is above < 120/80, so it is flagged High."
          ]
        }

        For each metric provide:
        - name in English
        - value as a numeric string
        - unit such as mg/dL, mmHg, %, g/L, 10^9/L
        - normalRange if visible or inferable from the report
        - status: "Normal", "Borderline", or "High"

        In evidenceTrace, write 2-5 concise patient-friendly bullets explaining which values were read and why they were flagged.
        If you cannot read the image or find no metrics, return {"metrics":[],"evidenceTrace":[]}
        """

        let rawText = try await CactusManager.shared.visionComplete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            imageData: imageData,
            maxTokens: 900
        )

        return try parseMetrics(from: rawText, labName: "Extracted by Gemma 4 Vision")
    }

    private func runTextInference(ocrText: String) async throws -> HealthReport {
        let systemPrompt = """
        You are a medical data extraction assistant. \
        The user message contains OCR text from a health checkup or blood test report. \
        Extract ALL health metrics you can identify. \
        Respond ONLY with one valid JSON object. No explanation, no markdown.
        """

        let userMessage = """
        Return this exact JSON structure:
        {
          "metrics": [
            {"name":"Blood Pressure","value":"138/89","unit":"mmHg","normalRange":"< 120/80","status":"High"}
          ],
          "evidenceTrace": [
            "Blood Pressure 138/89 mmHg is above < 120/80, so it is flagged High."
          ]
        }

        For each metric provide:
        - name (in English)
        - value (numeric string)
        - unit (e.g. mg/dL, mmHg, %)
        - normalRange (e.g. < 100, 18.5–24, > 40)
        - status: "Normal", "Borderline", or "High"

        In evidenceTrace, write 2-5 concise patient-friendly bullets explaining which values were read and why they were flagged.
        If you cannot read the image or find no metrics, return {"metrics":[],"evidenceTrace":[]}

        OCR TEXT:
        \(ocrText)
        """

        let rawText = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 900,
            temperature: 0.05
        )

        return try parseMetrics(from: rawText, labName: "Apple Vision OCR + Gemma 4")
    }

    // MARK: - Parse JSON → HealthReport

    private struct MetricSpec {
        let name: String
        let aliases: [String]
        let unit: String
        let normalRange: String
        let icon: String
        let evaluate: (String) -> HealthStatus
    }

    private func parseReportFromOCR(_ text: String) -> HealthReport? {
        let normalized = text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        let specs: [MetricSpec] = [
            MetricSpec(name: "Blood Pressure", aliases: ["Blood Pressure", "BP", "血壓"], unit: "mmHg", normalRange: "< 120/80", icon: "heart.fill") { value in
                let parts = value.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 2 else { return .normal }
                if parts[0] >= 130 || parts[1] >= 80 { return .warning }
                if parts[0] >= 120 { return .borderline }
                return .normal
            },
            MetricSpec(name: "Fasting Glucose", aliases: ["Fasting Glucose", "Glucose", "血糖"], unit: "mg/dL", normalRange: "< 100", icon: "drop.fill") { value in
                self.evaluateNumeric(value, normalHigh: 100, borderlineHigh: 110)
            },
            MetricSpec(name: "HbA1c", aliases: ["HbA1c", "A1c", "糖化血色素"], unit: "%", normalRange: "< 5.7", icon: "waveform.path.ecg") { value in
                self.evaluateNumeric(value, normalHigh: 5.7, borderlineHigh: 6.0)
            },
            MetricSpec(name: "LDL Cholesterol", aliases: ["LDL Cholesterol", "LDL", "低密度"], unit: "mg/dL", normalRange: "< 130", icon: "chart.line.uptrend.xyaxis") { value in
                self.evaluateNumeric(value, normalHigh: 130, borderlineHigh: 160)
            },
            MetricSpec(name: "HDL Cholesterol", aliases: ["HDL Cholesterol", "HDL", "高密度"], unit: "mg/dL", normalRange: "> 40", icon: "shield.fill") { value in
                guard let number = Double(value) else { return .normal }
                return number < 40 ? .borderline : .normal
            },
            MetricSpec(name: "Triglycerides", aliases: ["Triglycerides", "TG", "三酸甘油脂"], unit: "mg/dL", normalRange: "< 150", icon: "flame.fill") { value in
                self.evaluateNumeric(value, normalHigh: 150, borderlineHigh: 200)
            },
            MetricSpec(name: "Total Cholesterol", aliases: ["Total Cholesterol", "Cholesterol", "總膽固醇"], unit: "mg/dL", normalRange: "< 200", icon: "circle.hexagongrid.fill") { value in
                self.evaluateNumeric(value, normalHigh: 200, borderlineHigh: 240)
            },
            MetricSpec(name: "BMI", aliases: ["BMI", "Body Mass Index"], unit: "", normalRange: "18.5-24", icon: "figure.stand") { value in
                guard let number = Double(value) else { return .normal }
                if number >= 27 { return .warning }
                if number >= 24 || number < 18.5 { return .borderline }
                return .normal
            },
            MetricSpec(name: "Hemoglobin", aliases: ["Hemoglobin", "Hb", "血紅素"], unit: "g/L", normalRange: "135-165", icon: "drop.fill") { value in
                guard let number = Double(value) else { return .normal }
                if number < 120 || number > 175 { return .warning }
                if number < 135 || number > 165 { return .borderline }
                return .normal
            },
            MetricSpec(name: "Platelets", aliases: ["Platelets", "PLT", "血小板"], unit: "10^9/L", normalRange: "150-400", icon: "circle.grid.cross.fill") { value in
                guard let number = Double(value) else { return .normal }
                if number < 100 || number > 450 { return .warning }
                if number < 150 || number > 400 { return .borderline }
                return .normal
            }
        ]

        var metrics: [HealthMetric] = []
        for spec in specs {
            guard let value = firstValue(for: spec.aliases, in: normalized) else { continue }
            let status = spec.evaluate(value)
            metrics.append(
                HealthMetric(
                    name: spec.name,
                    value: value,
                    unit: spec.unit,
                    normalRange: spec.normalRange,
                    status: status,
                    icon: spec.icon,
                    progress: progress(for: status)
                )
            )
        }

        guard metrics.count >= 2 else { return nil }
        return HealthReport(
            metrics: metrics,
            reportDate: Date(),
            labName: "Extracted by Apple Vision OCR",
            evidenceTrace: buildFallbackTrace(metrics: metrics)
        )
    }

    private func firstValue(for aliases: [String], in text: String) -> String? {
        for alias in aliases {
            let escaped = NSRegularExpression.escapedPattern(for: alias)
            let pattern = #"(?i)"# + escaped + #"[^0-9]{0,30}(\d{2,3}\s*/\s*\d{2,3}|\d{1,4}(?:\.\d+)?)"#
            if let match = firstMatch(pattern: pattern, in: text) {
                return match.replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[valueRange])
    }

    private func evaluateNumeric(_ value: String, normalHigh: Double, borderlineHigh: Double) -> HealthStatus {
        guard let number = Double(value) else { return .normal }
        if number >= borderlineHigh { return .warning }
        if number >= normalHigh { return .borderline }
        return .normal
    }

    private func progress(for status: HealthStatus) -> Double {
        switch status {
        case .warning: return 0.82
        case .borderline: return 0.66
        case .normal: return 0.42
        }
    }

    private func parseMetrics(from text: String, labName: String) throws -> HealthReport {
        print("[HealthExtractor] Raw vision text (\(text.count) chars): \(text.prefix(220))")
        let cleaned = extractJSONObject(from: text)
        guard let data = cleaned.data(using: .utf8) else {
            print("[HealthExtractor] JSON parse failed: no UTF-8 data")
            throw CactusError.inferenceFailure("Health scan response was not valid UTF-8 JSON.")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            print("[HealthExtractor] JSON parse failed: invalid JSON")
            throw CactusError.inferenceFailure("Health scan response was not valid JSON.")
        }

        let parsed = parseHealthPayload(object)
        guard !parsed.metricDictionaries.isEmpty else {
            print("[HealthExtractor] JSON parse failed: unexpected shape \(type(of: object))")
            throw CactusError.inferenceFailure("Health scan response did not match the expected JSON schema.")
        }

        let metrics: [HealthMetric] = parsed.metricDictionaries.compactMap { dict in
            guard
                let name        = stringValue(dict["name"]),
                let value       = stringValue(dict["value"]),
                let unit        = stringValue(dict["unit"]),
                let normalRange = stringValue(dict["normalRange"] ?? dict["range"]),
                let statusStr   = stringValue(dict["status"])
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

        if metrics.isEmpty {
            throw CactusError.inferenceFailure("No health metrics were extracted from the selected image.")
        }

        return HealthReport(
            metrics:    metrics,
            reportDate: Date(),
            labName:    labName,
            evidenceTrace: parsed.evidenceTrace.isEmpty ? buildFallbackTrace(metrics: metrics) : parsed.evidenceTrace
        )
    }

    // MARK: - Helpers

    private typealias MetricDictionary = [String: Any]

    private func parseHealthPayload(_ object: Any) -> (metricDictionaries: [MetricDictionary], evidenceTrace: [String]) {
        if let dict = object as? [String: Any] {
            return parseHealthDictionary(dict)
        }
        if let dict = object as? NSDictionary {
            return parseHealthDictionary(dict.reduce(into: [:]) { result, pair in
                if let key = pair.key as? String {
                    result[key] = pair.value
                }
            })
        }
        if let array = object as? [[String: Any]] {
            return (array, [])
        }
        if let array = object as? [NSDictionary] {
            return (array.map { nsDict in
                nsDict.reduce(into: MetricDictionary()) { result, pair in
                    if let key = pair.key as? String {
                        result[key] = pair.value
                    }
                }
            }, [])
        }
        return ([], [])
    }

    private func parseHealthDictionary(_ dict: [String: Any]) -> (metricDictionaries: [MetricDictionary], evidenceTrace: [String]) {
        let metrics: [MetricDictionary]
        if let typed = dict["metrics"] as? [[String: Any]] {
            metrics = typed
        } else if let nsArray = dict["metrics"] as? [NSDictionary] {
            metrics = nsArray.map { nsDict in
                nsDict.reduce(into: MetricDictionary()) { result, pair in
                    if let key = pair.key as? String {
                        result[key] = pair.value
                    }
                }
            }
        } else if let nested = dict["data"] as? [String: Any],
                  let typed = nested["metrics"] as? [[String: Any]] {
            metrics = typed
        } else {
            metrics = []
        }

        let evidenceTrace = stringArray(dict["evidenceTrace"] ?? dict["reasoningTrace"] ?? dict["trace"])
        return (metrics, evidenceTrace)
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        case let value?:
            return String(describing: value)
        case nil:
            return nil
        }
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let array = value as? [String] {
            return array.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let array = value as? [Any] {
            return array.compactMap { stringValue($0) }
        }
        return []
    }

    private func extractJSONObject(from text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = stripped.firstIndex(of: "{"),
           let end   = stripped.lastIndex(of: "}") {
            return String(stripped[start...end])
        }
        if let start = stripped.firstIndex(of: "["),
           let end   = stripped.lastIndex(of: "]") {
            return String(stripped[start...end])
        }
        return stripped
    }

    private func buildFallbackTrace(metrics: [HealthMetric]) -> [String] {
        metrics.prefix(5).map { metric in
            "\(metric.name) \(metric.value)\(metric.unit) is compared with \(metric.normalRange), so it is flagged \(metric.status.rawValue)."
        }
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
