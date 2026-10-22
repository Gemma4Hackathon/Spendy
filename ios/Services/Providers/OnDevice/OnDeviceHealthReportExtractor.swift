import Foundation
import UIKit
import Vision

final class OnDeviceHealthReportExtractor: HealthReportExtracting {

    var isModelReady: Bool { CactusManager.shared.isReady }

    /// Fewer metrics than this from OCR moves on to the next fallback.
    private let minimumMetricCount = 2

    private func logSensitive(_ message: @autoclosure () -> String) {
        #if SPENDY_VERBOSE_LOGS
        print(message())
        #endif
    }

    // MARK: - HealthReportExtracting

    func extractHealthReport(imageData: Data) async throws -> HealthReport {
        // [PERF] measurement wrapper; the original logic lives in extractHealthReportImpl.
        let scope = PerfScope.begin("health_scan", extra: "image_bytes=\(imageData.count)")
        do {
            let report = try await extractHealthReportImpl(imageData: imageData)
            scope.end("result=ok metrics=\(report.metrics.count) lab=\"\(report.labName)\"")
            if PerfMonitor.verbose {
                for metric in report.metrics {
                    print("[PERF-RESULT] scan_metric name=\"\(metric.name)\" value=\"\(metric.value)\" unit=\"\(metric.unit)\" status=\(metric.status)")
                }
            }
            return report
        } catch {
            scope.end("result=error")
            throw error
        }
    }

    /// OCR first; Gemma 4 vision only as a fallback:
    /// 1. Apple Vision OCR reads the image.
    /// 2. Gemma 4 structures the OCR text; known metrics read straight from OCR table rows
    ///    fill keys it left out; the rule-based OCR parser covers fewer than 2 results.
    /// 3. Gemma 4 vision runs only if that still finds fewer than 2 metrics, and its values are
    ///    kept only if OCR read them on the metric's own row. On a full page Cactus's fixed
    ///    pixel budget leaves table text about 6 px tall and vision fills gaps with typical
    ///    values (bench/experiments.md), so it is never trusted unverified.
    /// 4. If OCR fails or finds no text, the image is rejected: no value is shown unverified.
    /// Status, reference range and evidence trace are decided in `HealthReportVerifier`.
    private func extractHealthReportImpl(imageData: Data) async throws -> HealthReport {
        let lines: [OCRLine]
        do {
            lines = try await withTimeout(seconds: 8) {
                try await self.recognizeTextLines(from: imageData)
            }
        } catch {
            // Without OCR text nothing can be verified, and unverified vision output is
            // typical values, not readings (a landscape photo returned TC 210, LDL 140).
            print("[HealthExtractor] Apple Vision OCR failed: \(error.localizedDescription)")
            logVerification(path: "ocr_failed", visionRan: false, vision: 0, visionVerified: 0, text: 0, final: 0)
            throw CactusError.inferenceFailure("The report text could not be read. Please try a clearer photo.")
        }
        guard !lines.isEmpty else {
            logVerification(path: "no_text", visionRan: false, vision: 0, visionVerified: 0, text: 0, final: 0)
            throw CactusError.inferenceFailure("No report text was found in the selected image.")
        }
        let ocrText = lines.map(\.text).joined(separator: "\n")
        print("[HealthExtractor] OCR text recognized (\(lines.count) lines, \(ocrText.count) chars).")
        PerfMonitor.logRawText(source: "ocr", text: lines.map {
            String(format: "y=%.4f h=%.4f | ", $0.midY, $0.height) + $0.text
        }.joined(separator: "\n"))

        // Known metrics read directly from OCR table rows; they only fill keys the model
        // left out (the text model can stop before the results table, e.g. IMG_9603).
        let tableMetrics = HealthReportVerifier.verify(HealthReportVerifier.tableCandidates(lines: lines), lines: lines, requireSameRow: true)

        var textCandidates: [MetricCandidate] = []
        if isModelReady {
            do {
                print("[HealthExtractor] Structuring OCR text with Gemma 4...")
                textCandidates = try await runTextInference(ocrText: ocrText)
            } catch {
                print("[HealthExtractor] Gemma 4 text structuring failed: \(error.localizedDescription)")
            }
        }
        let verifiedText = HealthReportVerifier.verify(textCandidates, lines: lines, requireSameRow: false)
        let textKeys = Set(verifiedText.map(\.key))
        var metrics = verifiedText + tableMetrics.filter { !textKeys.contains($0.key) }
        var tableFilled = metrics.count - verifiedText.count
        var path = "ocr_text"
        var labName = isModelReady ? "Apple Vision OCR + Gemma 4" : "Extracted by Apple Vision OCR"

        if metrics.count < minimumMetricCount {
            let ruleCandidates = ruleBasedCandidates(fromOCR: ocrText)
            let verifiedRules = HealthReportVerifier.verify(ruleCandidates, lines: lines, requireSameRow: false)
            if verifiedRules.count > metrics.count {
                print("[HealthExtractor] Using rule-based OCR parser (\(verifiedRules.count) metrics).")
                metrics = verifiedRules
                tableFilled = 0
                path = "ocr_rules"
                labName = "Extracted by Apple Vision OCR"
            }
        }

        var visionCandidates: [MetricCandidate]? = nil
        var verifiedVisionCount = 0
        if metrics.count < minimumMetricCount {
            visionCandidates = await visionCandidatesIfReady(imageData: imageData)
            let verifiedVision = HealthReportVerifier.verify(visionCandidates ?? [], lines: lines, requireSameRow: true)
            verifiedVisionCount = verifiedVision.count
            print("[HealthExtractor] OCR confirmed \(verifiedVision.count) of \(visionCandidates?.count ?? 0) Gemma 4 vision metrics.")
            let keys = Set(metrics.map(\.key))
            let added = verifiedVision.filter { !keys.contains($0.key) }
            if !added.isEmpty {
                metrics += added
                path = "vision_fallback"
                labName = "Gemma 4 Vision · verified by OCR"
            }
        }

        logVerification(path: path, visionRan: visionCandidates != nil, vision: visionCandidates?.count ?? 0,
                        visionVerified: verifiedVisionCount, text: verifiedText.count, tableFilled: tableFilled, final: metrics.count)
        guard !metrics.isEmpty else {
            throw CactusError.inferenceFailure("No health metrics were found in the selected image.")
        }
        return makeReport(metrics, labName: labName)
    }

    /// Gemma 4 vision candidates, or nil when the model is not loaded (vision did not run).
    private func visionCandidatesIfReady(imageData: Data) async -> [MetricCandidate]? {
        guard isModelReady else { return nil }
        do {
            print("[HealthExtractor] Trying Gemma 4 vision extraction...")
            return try await runVisionInference(imageData: imageData)
        } catch {
            print("[HealthExtractor] Gemma 4 vision failed: \(error.localizedDescription)")
            return []
        }
    }

    private func logVerification(path: String, visionRan: Bool, vision: Int, visionVerified: Int, text: Int, tableFilled: Int = 0, final: Int) {
        PerfMonitor.log("scan_verification", "path=\(path) vision_ran=\(visionRan) vision_metrics=\(vision) vision_verified=\(visionVerified) text_verified=\(text) table_filled=\(tableFilled) final=\(final)")
    }

    private func makeReport(_ metrics: [VerifiedMetric], labName: String) -> HealthReport {
        HealthReport(
            metrics: metrics.map { metric in
                HealthMetric(
                    name:        metric.name,
                    value:       metric.value,
                    unit:        metric.unit,
                    normalRange: metric.normalRange,
                    status:      metric.status,
                    icon:        iconForMetric(name: metric.name),
                    progress:    progress(for: metric.status)
                )
            },
            reportDate: Date(),
            labName: labName,
            evidenceTrace: HealthReportVerifier.evidenceTrace(for: metrics)
        )
    }

    // MARK: - OCR

    private func recognizeTextLines(from imageData: Data) async throws -> [OCRLine] {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage
        else {
            throw CactusError.inferenceFailure("The selected image could not be decoded.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let lock = NSLock()
                var didResume = false
                func resumeOnce(_ result: Result<[OCRLine], Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    switch result {
                    case .success(let lines):
                        continuation.resume(returning: lines)
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
                    let lines = observations.compactMap { observation -> OCRLine? in
                        guard let text = observation.topCandidates(1).first?.string,
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else { return nil }
                        return OCRLine(
                            text: text,
                            midY: Double(observation.boundingBox.midY),
                            height: Double(observation.boundingBox.height)
                        )
                    }
                    // No text is a result, not an OCR failure: the caller rejects the image.
                    resumeOnce(.success(lines))
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

    // MARK: - Vision / Text Inference

    private func runVisionInference(imageData: Data) async throws -> [MetricCandidate] {
        let systemPrompt = """
        You are a strict medical data extraction engine. \
        The user image is a health checkup or blood test report. \
        Read only visible lab table values directly from the image. \
        Output JSON only. Do not output markdown, headings, prose, summaries, or code fences.
        """

        // Name, value and unit only: status, reference range and evidence are decided in
        // HealthReportVerifier, so asking the model for them only adds decode time.
        let userMessage = """
        Extract every lab test result visible in this report image.

        Return exactly one JSON object using this schema:
        {"metrics":[{"name":"Blood Pressure","value":"138/89","unit":"mmHg"}]}

        For each result provide:
        - name: the test name in English
        - value: the result as a numeric string
        - unit: as printed, or "" if there is none

        Do not include reference ranges or flags as values.
        If you cannot read the image or find no results, return {"metrics":[]}

        The first character of your response must be { and the last character must be }.
        """

        let rawText = try await CactusManager.shared.visionComplete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            imageData: imageData,
            maxTokens: 800
        )
        return parseCandidates(from: rawText, perfSource: "health_vision")
    }

    private func runTextInference(ocrText: String) async throws -> [MetricCandidate] {
        let systemPrompt = """
        You are a medical data extraction assistant. \
        The user message contains noisy OCR text from a health checkup or blood test report. \
        Extract health metrics you can identify from imperfect OCR. \
        Do not infer missing values. Do not invent generic patient values. \
        Respond ONLY with one valid JSON object using the requested schema. No explanation, no markdown.
        """

        // Name, value and unit only; see runVisionInference.
        let userMessage = """
        Return one JSON object with this structure:
        {"metrics":[{"name":"Blood Pressure","value":"138/89","unit":"mmHg"}]}

        For each lab value or health marker in the OCR text provide:
        - name (in English)
        - value (numeric string)
        - unit (e.g. mg/dL, mmHg, %), or "" if there is none
        - Include every row of a results table.
        - Do not include reference ranges or flags as values.
        - Ignore report section numbers, dates, patient IDs, phone numbers, specimen IDs, and client information.
        - Do not return patient profile fields such as name, age, gender, weight, or height.
        - If you are unsure whether a number belongs to a health metric, omit it.

        If you find no metrics, return {"metrics":[]}

        OCR TEXT:
        \(ocrText)
        """

        let rawText = try await CactusManager.shared.complete(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 1_000,
            temperature: 0
        )
        return parseCandidates(from: rawText, perfSource: "health_ocr_text")
    }

    // MARK: - Rule-based OCR parser (last resort)

    private struct MetricSpec {
        let name: String
        let aliases: [String]
        let unit: String
        let normalRange: String
        let evaluate: (String) -> HealthStatus
    }

    private func ruleBasedCandidates(fromOCR text: String) -> [MetricCandidate] {
        let normalized = text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        let specs: [MetricSpec] = [
            MetricSpec(name: "Blood Pressure", aliases: ["Blood Pressure", "BP", "血壓"], unit: "mmHg", normalRange: "< 120/80") { value in
                let parts = value.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 2 else { return .normal }
                if parts[0] >= 130 || parts[1] >= 80 { return .warning }
                if parts[0] >= 120 { return .borderline }
                return .normal
            },
            MetricSpec(name: "Fasting Glucose", aliases: ["Fasting Glucose", "Glucose", "血糖"], unit: "mg/dL", normalRange: "< 100") { value in
                self.evaluateNumeric(value, normalHigh: 100, borderlineHigh: 110)
            },
            MetricSpec(name: "HbA1c", aliases: ["HbA1c", "A1c", "糖化血色素"], unit: "%", normalRange: "< 5.7") { value in
                self.evaluateNumeric(value, normalHigh: 5.7, borderlineHigh: 6.0)
            },
            MetricSpec(name: "LDL Cholesterol", aliases: ["LDL Cholesterol", "LDL", "低密度"], unit: "mg/dL", normalRange: "< 130") { value in
                self.evaluateNumeric(value, normalHigh: 130, borderlineHigh: 160)
            },
            MetricSpec(name: "HDL Cholesterol", aliases: ["HDL Cholesterol", "HDL", "高密度"], unit: "mg/dL", normalRange: "> 40") { value in
                guard let number = Double(value) else { return .normal }
                return number < 40 ? .borderline : .normal
            },
            MetricSpec(name: "Triglycerides", aliases: ["Triglycerides", "TG", "三酸甘油脂"], unit: "mg/dL", normalRange: "< 150") { value in
                self.evaluateNumeric(value, normalHigh: 150, borderlineHigh: 200)
            },
            MetricSpec(name: "Total Cholesterol", aliases: ["Total Cholesterol", "Cholesterol", "總膽固醇"], unit: "mg/dL", normalRange: "< 200") { value in
                self.evaluateNumeric(value, normalHigh: 200, borderlineHigh: 240)
            },
            MetricSpec(name: "BMI", aliases: ["BMI", "Body Mass Index"], unit: "", normalRange: "18.5-24") { value in
                guard let number = Double(value) else { return .normal }
                if number >= 27 { return .warning }
                if number >= 24 || number < 18.5 { return .borderline }
                return .normal
            },
            MetricSpec(name: "Hemoglobin", aliases: ["Hemoglobin", "Hb", "血紅素"], unit: "g/L", normalRange: "135-165") { value in
                guard let number = Double(value) else { return .normal }
                if number < 120 || number > 175 { return .warning }
                if number < 135 || number > 165 { return .borderline }
                return .normal
            },
            MetricSpec(name: "Platelets", aliases: ["Platelets", "PLT", "血小板"], unit: "10^9/L", normalRange: "150-400") { value in
                guard let number = Double(value) else { return .normal }
                if number < 100 || number > 450 { return .warning }
                if number < 150 || number > 400 { return .borderline }
                return .normal
            }
        ]

        return specs.compactMap { spec in
            guard let value = firstValue(for: spec.aliases, in: normalized),
                  isPlausibleMetricValue(name: spec.name, value: value)
            else { return nil }
            return MetricCandidate(
                name: spec.name,
                value: value,
                unit: spec.unit,
                normalRange: spec.normalRange,
                modelStatus: spec.evaluate(value)
            )
        }
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

    // MARK: - Parse model JSON → candidates

    /// Metric candidates from a model response; empty when it holds none. Only name and
    /// value are required, since status and range are decided by HealthReportVerifier.
    private func parseCandidates(from text: String, perfSource: String) -> [MetricCandidate] {
        print("[HealthExtractor] Raw model text received (\(text.count) chars).")
        logSensitive("[HealthExtractor] Raw model text preview: \(text.prefix(220))")
        let result = LenientJSON.parse(text)
        PerfMonitor.logJSONParse(source: perfSource, raw: text, result: result)
        guard let object = result.object else {
            print("[HealthExtractor] JSON parse failed: invalid JSON")
            return []
        }

        let candidates = parseHealthPayload(object).compactMap(MetricCandidate.init(json:))
        if candidates.isEmpty {
            print("[HealthExtractor] No metrics in model JSON (\(type(of: object))).")
            PerfMonitor.logParseFailure(source: perfSource, reason: "no_metrics", raw: text, cleaned: result.candidate)
        }
        return candidates
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

    private func parseHealthPayload(_ object: Any) -> [MetricDictionary] {
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
            return array
        }
        if let array = object as? [NSDictionary] {
            return array.map { nsDict in
                nsDict.reduce(into: MetricDictionary()) { result, pair in
                    if let key = pair.key as? String {
                        result[key] = pair.value
                    }
                }
            }
        }
        return []
    }

    private func parseHealthDictionary(_ dict: [String: Any]) -> [MetricDictionary] {
        if let typed = dict["metrics"] as? [[String: Any]] {
            return typed
        }
        if let nsArray = dict["metrics"] as? [NSDictionary] {
            return nsArray.map { nsDict in
                nsDict.reduce(into: MetricDictionary()) { result, pair in
                    if let key = pair.key as? String {
                        result[key] = pair.value
                    }
                }
            }
        }
        if let nested = dict["data"] as? [String: Any],
           let typed = nested["metrics"] as? [[String: Any]] {
            return typed
        }
        return metricsFromFlatPayload(dict)
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
