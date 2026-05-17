import Foundation
import UIKit
import Vision

final class OnDeviceHealthReportExtractor: HealthReportExtracting {

    var isModelReady: Bool { CactusManager.shared.isReady }

    private let preferredMinimumMetricCount = 5
    private let longOCRTextThreshold = 1_000

    private func logSensitive(_ message: @autoclosure () -> String) {
        #if SPENDY_VERBOSE_LOGS
        print(message())
        #endif
    }

    // MARK: - HealthReportExtracting

    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        var releasedModelForOCR = false
        if isModelReady {
            do {
                print("[HealthExtractor] Trying Gemma 4 vision extraction...")
                return try await runVisionInference(imageData: imageData)
            } catch {
                print("[HealthExtractor] Gemma 4 vision failed. Releasing model before Apple Vision OCR: \(error.localizedDescription)")
                await CactusManager.shared.releaseModelForMemoryPressure()
                releasedModelForOCR = true
            }
        }

        let text = try await withTimeout(seconds: 8) {
            try await self.recognizeText(from: imageData)
        }
        print("[HealthExtractor] OCR text recognized (\(text.count) chars).")
        logSensitive("[HealthExtractor] OCR text preview: \(text.prefix(300))")

        let directOCRReport = parseReportFromOCR(text)
        if let report = directOCRReport,
           shouldAcceptDirectOCRReport(report, ocrText: text) {
            reloadModelIfNeeded(releasedModelForOCR)
            return report
        }
        if let report = directOCRReport {
            print("[HealthExtractor] Direct OCR parser extracted only \(report.metrics.count) metrics from \(text.count) chars; using Gemma 4 text structuring.")
        }

        if releasedModelForOCR {
            print("[HealthExtractor] OCR text found but direct parser failed. Reloading Gemma 4 for OCR structuring.")
            try await reloadModelForTextInference()
            return try await runTextInferenceWithFallback(ocrText: text, fallbackReport: directOCRReport)
        }

        guard isModelReady else {
            throw CactusError.modelNotLoaded
        }
        let report = try await runTextInferenceWithFallback(ocrText: text, fallbackReport: directOCRReport)
        reloadModelIfNeeded(releasedModelForOCR)
        return report
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
                let lock = NSLock()
                var didResume = false
                func resumeOnce(_ result: Result<String, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    switch result {
                    case .success(let text):
                        continuation.resume(returning: text)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        resumeOnce(.failure(error))
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n")
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        resumeOnce(.failure(CactusError.inferenceFailure("No text was recognized in the selected image.")))
                    } else {
                        resumeOnce(.success(text))
                    }
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]

                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    resumeOnce(.failure(error))
                }
            }
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw CactusError.inferenceFailure("Apple Vision OCR timed out.")
            }

            guard let result = try await group.next() else {
                throw CactusError.inferenceFailure("Apple Vision OCR did not return a result.")
            }
            group.cancelAll()
            return result
        }
    }

    private func reloadModelIfNeeded(_ shouldReload: Bool) {
        guard shouldReload else { return }
        Task.detached(priority: .utility) {
            await CactusManager.shared.loadModel()
        }
    }

    private func reloadModelForTextInference() async throws {
        await CactusManager.shared.loadModel()
        guard isModelReady else {
            throw CactusError.inferenceFailure("The OCR text was read, but the local model could not be reloaded to structure it.")
        }
    }

    // MARK: - Vision / Text Inference

    private func runVisionInference(imageData: Data) async throws -> HealthReport {
        let systemPrompt = """
        You are a strict medical data extraction engine. \
        The user image is a health checkup or blood test report. \
        Read only visible lab table values directly from the image. \
        Output JSON only. Do not output markdown, headings, prose, summaries, or code fences.
        """

        let userMessage = """
        Extract all visible health metrics from this report image.

        Return exactly one JSON object using this schema:
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

        The first character of your response must be { and the last character must be }.
        """

        let rawText = try await CactusManager.shared.visionComplete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            imageData: imageData,
            maxTokens: 1_200
        )

        do {
            let report = try parseMetrics(from: rawText, labName: "Extracted by Gemma 4 Vision")
            guard reportHasPreferredCoverage(report) else {
                print("[HealthExtractor] Gemma 4 vision extracted only \(report.metrics.count) metrics; using OCR + Gemma text structuring.")
                return try await recoverWithOCRTextStructuring(
                    imageData: imageData,
                    fallbackReport: report,
                    reason: "Gemma 4 vision returned too few metrics."
                )
            }
            return report
        } catch {
            print("[HealthExtractor] Gemma 4 vision returned non-JSON; trying local JSON repair.")
            let repairedReport = try await runVisionJSONRepair(visionText: rawText)
            guard reportHasPreferredCoverage(repairedReport) else {
                print("[HealthExtractor] Gemma 4 vision repair extracted only \(repairedReport.metrics.count) metrics; using OCR + Gemma text structuring.")
                return try await recoverWithOCRTextStructuring(
                    imageData: imageData,
                    fallbackReport: repairedReport,
                    reason: "Gemma 4 vision repair returned too few metrics."
                )
            }
            return repairedReport
        }
    }

    private func runVisionJSONRepair(visionText: String) async throws -> HealthReport {
        let systemPrompt = """
        You convert health report extraction text into strict JSON. \
        Use only values explicitly present in the user text. \
        Output JSON only. Do not output markdown, explanation, or code fences.
        """

        let userMessage = """
        Convert the following Gemma 4 vision extraction into this exact JSON schema:
        {
          "metrics": [
            {"name":"Blood Pressure","value":"138/89","unit":"mmHg","normalRange":"< 120/80","status":"High"}
          ],
          "evidenceTrace": [
            "Blood Pressure 138/89 mmHg is above < 120/80, so it is flagged High."
          ]
        }

        Rules:
        - Keep only real health metrics with clear values and units.
        - Ignore patient information, specimen information, client information, IDs, dates, and section numbers.
        - If no clear metrics exist, return {"metrics":[],"evidenceTrace":[]}
        - The first character of your response must be { and the last character must be }.

        VISION EXTRACTION TEXT:
        \(visionText)
        """

        let repairedText = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 1_400,
            temperature: 0.05
        )

        return try parseMetrics(from: repairedText, labName: "Gemma 4 Vision + JSON Repair")
    }

    private func recoverWithOCRTextStructuring(
        imageData: Data,
        fallbackReport: HealthReport?,
        reason: String
    ) async throws -> HealthReport {
        print("[HealthExtractor] \(reason) Releasing model before OCR recovery.")
        await CactusManager.shared.releaseModelForMemoryPressure()

        let text = try await withTimeout(seconds: 8) {
            try await self.recognizeText(from: imageData)
        }
        print("[HealthExtractor] OCR recovery text recognized (\(text.count) chars).")
        logSensitive("[HealthExtractor] OCR recovery text preview: \(text.prefix(300))")

        let directOCRReport = parseReportFromOCR(text)
        let bestFallback = betterReport(directOCRReport, fallbackReport)

        if let report = directOCRReport,
           shouldAcceptDirectOCRReport(report, ocrText: text),
           report.metrics.count >= (fallbackReport?.metrics.count ?? 0) {
            reloadModelIfNeeded(true)
            return report
        }

        try await reloadModelForTextInference()
        return try await runTextInferenceWithFallback(ocrText: text, fallbackReport: bestFallback)
    }

    private func runTextInference(ocrText: String) async throws -> HealthReport {
        let systemPrompt = """
        You are a medical data extraction assistant. \
        The user message contains noisy OCR text from a health checkup or blood test report. \
        Extract health metrics you can identify from imperfect OCR. \
        Do not infer missing values. Do not invent generic patient values. \
        Respond ONLY with one valid JSON object using the requested schema. No explanation, no markdown.
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
        - Ignore report section numbers, dates, patient IDs, phone numbers, specimen IDs, and client information.
        - Do not return patient profile fields such as name, age, gender, weight, or height.
        - If you are unsure whether a number belongs to a health metric, omit it.
        - Keep only metrics that are clearly lab values or health markers.

        In evidenceTrace, write 2-5 concise patient-friendly bullets explaining which values were read and why they were flagged.
        If you cannot read the image or find no metrics, return {"metrics":[],"evidenceTrace":[]}

        OCR TEXT:
        \(ocrText)
        """

        let rawText = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 1_600,
            temperature: 0.05
        )

        return try parseMetrics(from: rawText, labName: "Apple Vision OCR + Gemma 4")
    }

    private func runTextInferenceWithFallback(
        ocrText: String,
        fallbackReport: HealthReport?
    ) async throws -> HealthReport {
        do {
            let report = try await runTextInference(ocrText: ocrText)
            if !reportHasPreferredCoverage(report) {
                print("[HealthExtractor] Gemma 4 text structuring returned \(report.metrics.count) metrics; keeping best available report.")
            }
            return betterReport(report, fallbackReport) ?? report
        } catch {
            if let fallbackReport {
                print("[HealthExtractor] Gemma 4 text structuring failed; returning fallback report with \(fallbackReport.metrics.count) metrics: \(error.localizedDescription)")
                return fallbackReport
            }
            throw error
        }
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
            guard isPlausibleMetricValue(name: spec.name, value: value) else { continue }
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

    private func isPlausibleMetricValue(name: String, value: String) -> Bool {
        let normalizedName = name.lowercased()
        if normalizedName.contains("pressure") {
            let parts = value.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { return false }
            return (70...240).contains(parts[0]) && (40...140).contains(parts[1])
        }

        guard let number = Double(value) else { return false }
        if normalizedName.contains("glucose") { return (40...400).contains(number) }
        if normalizedName.contains("hba1c") { return (3...15).contains(number) }
        if normalizedName.contains("ldl") { return (20...400).contains(number) }
        if normalizedName.contains("hdl") { return (10...150).contains(number) }
        if normalizedName.contains("triglyceride") { return (20...1000).contains(number) }
        if normalizedName.contains("total cholesterol") { return (80...400).contains(number) }
        if normalizedName.contains("bmi") { return (10...80).contains(number) }
        if normalizedName.contains("hemoglobin") { return (50...250).contains(number) }
        if normalizedName.contains("platelet") { return (20...1000).contains(number) }
        return true
    }

    private func progress(for status: HealthStatus) -> Double {
        switch status {
        case .warning: return 0.82
        case .borderline: return 0.66
        case .normal: return 0.42
        }
    }

    private func reportHasPreferredCoverage(_ report: HealthReport) -> Bool {
        report.metrics.count >= preferredMinimumMetricCount
    }

    private func shouldAcceptDirectOCRReport(_ report: HealthReport, ocrText: String) -> Bool {
        if ocrText.count >= longOCRTextThreshold {
            return reportHasPreferredCoverage(report)
        }
        return report.metrics.count >= 2
    }

    private func betterReport(_ first: HealthReport?, _ second: HealthReport?) -> HealthReport? {
        switch (first, second) {
        case let (first?, second?):
            return first.metrics.count >= second.metrics.count ? first : second
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }

    private func parseMetrics(from text: String, labName: String) throws -> HealthReport {
        print("[HealthExtractor] Raw model text received (\(text.count) chars).")
        logSensitive("[HealthExtractor] Raw model text preview: \(text.prefix(220))")
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

            return HealthMetric(
                name:        name,
                value:       value,
                unit:        unit,
                normalRange: normalRange,
                status:      status,
                icon:        iconForMetric(name: name),
                progress:    progress(for: status)
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

    private struct FlatMetricSpec {
        let keys: [String]
        let name: String
        let unit: String
        let normalRange: String
        let evaluate: (String) -> HealthStatus
    }

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
            metrics = metricsFromFlatPayload(dict)
        }

        let evidenceTrace = stringArray(dict["evidenceTrace"] ?? dict["reasoningTrace"] ?? dict["trace"])
        return (metrics, evidenceTrace)
    }

    private func metricsFromFlatPayload(_ dict: [String: Any]) -> [MetricDictionary] {
        let specs: [FlatMetricSpec] = [
            FlatMetricSpec(keys: ["blood_pressure", "bloodPressure", "bp"], name: "Blood Pressure", unit: "mmHg", normalRange: "< 120/80") { value in
                let parts = value.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 2 else { return .normal }
                if parts[0] >= 130 || parts[1] >= 80 { return .warning }
                if parts[0] >= 120 { return .borderline }
                return .normal
            },
            FlatMetricSpec(keys: ["fasting_glucose", "fastingGlucose", "glucose", "blood_glucose"], name: "Fasting Glucose", unit: "mg/dL", normalRange: "< 100") { value in
                self.evaluateNumeric(value, normalHigh: 100, borderlineHigh: 110)
            },
            FlatMetricSpec(keys: ["hba1c", "a1c", "hemoglobin_a1c"], name: "HbA1c", unit: "%", normalRange: "< 5.7") { value in
                self.evaluateNumeric(value, normalHigh: 5.7, borderlineHigh: 6.0)
            },
            FlatMetricSpec(keys: ["cholesterol_total", "total_cholesterol", "totalCholesterol", "cholesterol"], name: "Total Cholesterol", unit: "mg/dL", normalRange: "< 200") { value in
                self.evaluateNumeric(value, normalHigh: 200, borderlineHigh: 240)
            },
            FlatMetricSpec(keys: ["ldl", "ldl_cholesterol", "ldlCholesterol"], name: "LDL Cholesterol", unit: "mg/dL", normalRange: "< 130") { value in
                self.evaluateNumeric(value, normalHigh: 130, borderlineHigh: 160)
            },
            FlatMetricSpec(keys: ["hdl", "hdl_cholesterol", "hdlCholesterol"], name: "HDL Cholesterol", unit: "mg/dL", normalRange: "> 40") { value in
                guard let number = Double(self.numericString(from: value)) else { return .normal }
                return number < 40 ? .borderline : .normal
            },
            FlatMetricSpec(keys: ["triglycerides", "tg"], name: "Triglycerides", unit: "mg/dL", normalRange: "< 150") { value in
                self.evaluateNumeric(value, normalHigh: 150, borderlineHigh: 200)
            },
            FlatMetricSpec(keys: ["bmi", "body_mass_index", "bodyMassIndex"], name: "BMI", unit: "", normalRange: "18.5-24") { value in
                guard let number = Double(self.numericString(from: value)) else { return .normal }
                if number >= 27 { return .warning }
                if number >= 24 || number < 18.5 { return .borderline }
                return .normal
            },
            FlatMetricSpec(keys: ["hemoglobin", "hb"], name: "Hemoglobin", unit: "g/L", normalRange: "135-165") { value in
                guard let number = Double(self.numericString(from: value)) else { return .normal }
                if number < 120 || number > 175 { return .warning }
                if number < 135 || number > 165 { return .borderline }
                return .normal
            },
            FlatMetricSpec(keys: ["platelets", "plt"], name: "Platelets", unit: "10^9/L", normalRange: "150-400") { value in
                guard let number = Double(self.numericString(from: value)) else { return .normal }
                if number < 100 || number > 450 { return .warning }
                if number < 150 || number > 400 { return .borderline }
                return .normal
            }
        ]

        let lowercasedKeys = Dictionary(uniqueKeysWithValues: dict.keys.map { ($0.lowercased(), $0) })
        return specs.compactMap { spec in
            guard let sourceKey = spec.keys.compactMap({ lowercasedKeys[$0.lowercased()] }).first,
                  let rawValue = stringValue(dict[sourceKey])
            else { return nil }

            let extractedValue = metricValue(from: rawValue)
            guard isPlausibleMetricValue(name: spec.name, value: extractedValue) else { return nil }
            let status = spec.evaluate(extractedValue)
            return [
                "name": spec.name,
                "value": extractedValue,
                "unit": unitValue(from: rawValue) ?? spec.unit,
                "normalRange": spec.normalRange,
                "status": status.rawValue
            ]
        }
    }

    private func metricValue(from rawValue: String) -> String {
        let cleaned = rawValue
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let pressure = firstMatch(pattern: #"(\d{2,3}\s*/\s*\d{2,3})"#, in: cleaned) {
            return pressure.replacingOccurrences(of: " ", with: "")
        }
        return numericString(from: cleaned)
    }

    private func numericString(from rawValue: String) -> String {
        firstMatch(pattern: #"(-?\d{1,4}(?:\.\d+)?)"#, in: rawValue) ?? rawValue
    }

    private func unitValue(from rawValue: String) -> String? {
        let units = ["mg/dL", "mmHg", "%", "g/L", "g/dL", "kg/m2", "10^9/L"]
        return units.first { rawValue.localizedCaseInsensitiveContains($0) }
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
