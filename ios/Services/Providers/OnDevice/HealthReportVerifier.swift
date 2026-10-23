import Foundation

// MARK: - HealthReportVerifier
// Decides which model-extracted lab values to trust and what status to show.
// Gemma 4 vision invents plausible values on dense lab tables (phase 1: 0-2 of 8 correct),
// so a value is kept only if Apple Vision OCR read the same number on the same table row
// as the metric's name. Status comes from the report itself (Flag column, then printed
// reference range), then a standard reference table, and only last from the model.
// Foundation only, so it can be exercised on macOS against real OCR output.

/// One recognized OCR line (Vision normalized coordinates, origin bottom-left).
nonisolated struct OCRLine {
    let text: String
    let midY: Double
    let height: Double
}

/// A metric as the model returned it, before verification.
nonisolated struct MetricCandidate {
    var name: String
    var value: String
    var unit: String
    var normalRange: String
    var modelStatus: HealthStatus?
}

nonisolated extension MetricCandidate {
    /// Reads one metric object from model JSON. Only `name` and `value` are required;
    /// numbers are accepted where strings are expected.
    init?(json: [String: Any]) {
        func string(_ key: String) -> String? {
            switch json[key] {
            case let text as String:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case let number as NSNumber:
                return number.stringValue
            default:
                return nil
            }
        }
        guard let name = string("name"), let value = string("value") else { return nil }
        self.name = name
        self.value = value
        self.unit = string("unit") ?? ""
        self.normalRange = string("normalRange") ?? string("range") ?? ""
        switch string("status")?.lowercased() {
        case "high", "low", "warning", "abnormal": modelStatus = .warning
        case "borderline": modelStatus = .borderline
        case "normal": modelStatus = .normal
        default: modelStatus = nil
        }
    }
}

nonisolated struct VerifiedMetric {
    enum StatusBasis {
        case reportFlag, reportRange, standardRange, model
    }

    let key: String
    let name: String
    let value: String
    let unit: String
    let normalRange: String
    let status: HealthStatus
    let statusBasis: StatusBasis
    /// False when no OCR text was available to check the value against.
    let verified: Bool
}

nonisolated enum HealthReportVerifier {

    /// Keeps candidates whose value OCR read on the metric's own row. With
    /// `requireSameRow == false` a value that appears anywhere as a standalone number
    /// is also accepted (used for the OCR-text path, whose input is the OCR text itself).
    static func verify(_ candidates: [MetricCandidate], lines: [OCRLine], requireSameRow: Bool) -> [VerifiedMetric] {
        var seenKeys = Set<String>()
        var result: [VerifiedMetric] = []

        for candidate in candidates {
            guard let value = normalizedValue(candidate.value) else { continue }
            let reference = Reference.match(tokens(candidate.name))
            let key = reference?.key ?? normalizedKey(candidate.name)
            guard !seenKeys.contains(key) else { continue }
            // Risk estimates ("8-Year Diabetes Risk 7%") are computed, not measured, and are
            // rated on a graphic scale Swift cannot read, so no status shown for them is trustworthy.
            if reference == nil, isEstimate(candidate.name) { continue }
            // An OCR misread can still be "on the report" ("2.0" read as "20" for a ratio).
            if let plausible = plausibleReadings[key], let number = Double(value), !plausible.contains(number) { continue }

            let row = rowEvidence(value: value, reference: reference, name: candidate.name, lines: lines)
            if row == nil {
                guard !requireSameRow, appearsAnywhere(value, lines: lines) else { continue }
            }

            seenKeys.insert(key)
            result.append(resolve(candidate, value: value, reference: reference, key: key,
                                  row: row))
        }
        return result
    }

    /// A known metric read from a table row, with the OCR lines it came from.
    struct TableReading {
        let candidate: MetricCandidate
        /// Indices into the OCR lines: the label line and the reading line.
        let lineIndices: [Int]
    }

    /// Reads known metrics straight from table rows: a line naming a metric plus, on the
    /// same row, a line that starts with its reading ("115 mg/dL"). Reference-range lines
    /// and implausible readings (OCR "2.0" -> "20" for a ratio) are skipped. Used to fill
    /// rows the text model left out; results still go through `verify`.
    /// A key can get several candidates; `verify` keeps the first one confirmed on its row.
    static func tableReadings(lines: [OCRLine]) -> [TableReading] {
        var result: [TableReading] = []
        for (labelIndex, label) in lines.enumerated() {
            guard isNameLine(label.text),
                  let reference = Reference.match(tokens(label.text)),
                  let plausible = plausibleReadings[reference.key]
            else { continue }

            let readings = lines.indices
                .filter { $0 != labelIndex && abs(lines[$0].midY - label.midY) < 0.6 * max(lines[$0].height, label.height) }
                .filter { lines[$0].text.trimmingCharacters(in: .whitespaces).first?.isNumber == true && rangeExpression(in: lines[$0].text) == nil }
                .compactMap { index -> (distance: Double, value: String, index: Int)? in
                    guard let token = standaloneNumberTokens(in: lines[index].text).first,
                          let number = Double(token), plausible.contains(number)
                    else { return nil }
                    return (abs(lines[index].midY - label.midY), token, index)
                }
            guard let closest = readings.min(by: { $0.distance < $1.distance }) else { continue }

            let candidate = MetricCandidate(name: reference.displayName, value: closest.value,
                                            unit: "", normalRange: "", modelStatus: nil)
            result.append(TableReading(candidate: candidate, lineIndices: [labelIndex, closest.index]))
        }
        return result
    }

    static func tableCandidates(lines: [OCRLine]) -> [MetricCandidate] {
        tableReadings(lines: lines).map(\.candidate)
    }

    /// Readings outside these are OCR errors, not results. Blood pressure is left out:
    /// table rows split it into systolic and diastolic lines.
    private static let plausibleReadings: [String: ClosedRange<Double>] = [
        "hba1c": 3...20, "glucose": 20...700, "chol_hdl_ratio": 0.5...15, "non_hdl": 20...400,
        "ldl": 10...400, "hdl": 5...200, "triglycerides": 10...3000, "total_cholesterol": 50...600,
        "bmi": 10...80, "hemoglobin": 3...250, "platelets": 10...1500
    ]

    /// One patient-facing sentence per metric, consistent with the final value and status.
    static func evidenceTrace(for metrics: [VerifiedMetric]) -> [String] {
        metrics.map { metric in
            let reading = "\(metric.name) \(metric.value)\(metric.unit.isEmpty ? "" : " \(metric.unit)")"
            let range = metric.normalRange.isEmpty ? "" : " (reference \(metric.normalRange))"
            switch metric.statusBasis {
            case .reportFlag:
                return "\(reading) is marked \(metric.status.rawValue) on the report\(range)."
            case .reportRange:
                let position = metric.status == .normal ? "within" : "outside"
                return "\(reading) is \(position) the report's reference range \(metric.normalRange), so it is flagged \(metric.status.rawValue)."
            case .standardRange:
                return "\(reading) is compared with the standard range \(metric.normalRange), so it is flagged \(metric.status.rawValue)."
            case .model:
                return "\(reading) is flagged \(metric.status.rawValue) as read by Gemma 4\(range)."
            }
        }
    }

    // MARK: - Status

    private static func resolve(
        _ candidate: MetricCandidate,
        value: String,
        reference: Reference?,
        key: String,
        row: RowEvidence?
    ) -> VerifiedMetric {
        // Reference range printed on the report: prefer what OCR read on the metric's own row.
        // The model's range counts only if its numbers are on that row (it can shift the
        // range column by one row).
        let modelRange = candidate.normalRange.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelRangeNumbers = allNumbers(in: modelRange)
        let modelRangeOnRow = !modelRangeNumbers.isEmpty
            && (row.map { row in modelRangeNumbers.allSatisfy { row.numbers.contains($0) } } ?? false)
        let printedRange = row?.rangeText ?? (modelRangeOnRow ? modelRange : nil)
        let parsedRange = printedRange.flatMap(NumericRange.init)
        let number = Double(value)

        let status: HealthStatus
        let basis: VerifiedMetric.StatusBasis
        if let flag = row?.flag {
            status = flag
            basis = .reportFlag
        } else if let parsedRange, let number {
            status = parsedRange.contains(number) ? .normal : .warning
            basis = .reportRange
        } else if let reference {
            status = reference.evaluate(value)
            basis = .standardRange
        } else {
            status = candidate.modelStatus ?? .normal
            basis = .model
        }

        let displayRange = printedRange ?? reference?.range ?? ""

        let unit = candidate.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return VerifiedMetric(
            key: key,
            name: reference?.displayName ?? correctedName(candidate.name),
            value: value,
            unit: unit.isEmpty ? (reference?.unit ?? "") : unit,
            normalRange: displayRange,
            status: status,
            statusBasis: basis,
            verified: true
        )
    }

    // MARK: - OCR matching

    /// What OCR read on the table row that holds a metric's value.
    private struct RowEvidence {
        /// The report's Normal/High marking on the row, if any.
        let flag: HealthStatus?
        /// Every number on the row, including range bounds.
        let numbers: Set<Double>
        /// A reference range printed on the row, e.g. "65-99" or "< 5.7".
        let rangeText: String?
    }

    /// Finds a row (OCR lines at the same height) that holds `value` and names this metric.
    private static func rowEvidence(value: String, reference: Reference?, name: String, lines: [OCRLine]) -> RowEvidence? {
        let nameTokens = significantTokens(name)
        for line in lines where containsValue(value, in: line.text) {
            let row = lines.filter { abs($0.midY - line.midY) < 0.6 * max($0.height, line.height) }
            // Names only: a unit on a value line ("6.1% of total Hgb") is not a metric name.
            let rowTokens = Set(row.filter { isNameLine($0.text) }.flatMap { tokens($0.text) })
            let rowMatches: Bool
            if let reference {
                rowMatches = Reference.match(rowTokens)?.key == reference.key
            } else {
                rowMatches = !nameTokens.isEmpty && nameTokens.isSubset(of: rowTokens)
            }
            guard rowMatches else { continue }
            return RowEvidence(
                flag: flag(in: rowTokens),
                numbers: Set(row.flatMap { allNumbers(in: $0.text) }),
                rangeText: row.lazy.compactMap { rangeExpression(in: $0.text) }.first
            )
        }
        return nil
    }

    /// A line that can name a metric: it does not start with a reading ("115 mg/dL", "6.1%").
    private static func isNameLine(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).first?.isNumber != true
    }

    /// The first range expression in a line: "65-99", "< 5.7", "≤5.0", ">OR=46".
    private static func rangeExpression(in text: String) -> String? {
        let pattern = #"(?:[<>≤≥]=?\s*(?:OR\s*=\s*)?\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*[-–]\s*\d+(?:\.\d+)?)"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[match])
    }

    private static func flag(in rowTokens: Set<String>) -> HealthStatus? {
        if !rowTokens.isDisjoint(with: ["high", "low", "abnormal", "critical"]) { return .warning }
        if rowTokens.contains("borderline") { return .borderline }
        if rowTokens.contains("normal") { return .normal }
        return nil
    }

    private static func appearsAnywhere(_ value: String, lines: [OCRLine]) -> Bool {
        lines.contains { containsValue(value, in: $0.text) }
    }

    private static func containsValue(_ value: String, in text: String) -> Bool {
        if value.contains("/") {
            return text.replacingOccurrences(of: " ", with: "").contains(value)
        }
        guard let target = Double(value) else { return false }
        return standaloneNumbers(in: text).contains(target)
    }

    /// Numbers that stand as a reading on their own: not part of a word ("A1c"),
    /// not a range bound ("<150", "65-99", ">OR=46"), not a fraction part ("120/80").
    static func standaloneNumbers(in text: String) -> [Double] {
        standaloneNumberTokens(in: text).compactMap(Double.init)
    }

    /// `standaloneNumbers` as written in the text, so "2.0" keeps its decimal.
    private static func standaloneNumberTokens(in text: String) -> [String] {
        let characters = Array(text)
        var numbers: [String] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else { index += 1; continue }
            let start = index
            while index < characters.count, characters[index].isNumber || characters[index] == "." {
                index += 1
            }
            var end = index
            while end > start, characters[end - 1] == "." { end -= 1 }
            let token = String(characters[start..<end])

            let before = start > 0 ? characters[start - 1] : nil
            let previousNonSpace = characters[..<start].last { !$0.isWhitespace }
            let nextNonSpace = characters[end...].first { !$0.isWhitespace }
            let attachedToWord = before.map { $0.isLetter } ?? false
            let rangeBound = previousNonSpace.map { "<>=≤≥-–/".contains($0) } ?? false
            let rangeStart = nextNonSpace.map { "-–/".contains($0) } ?? false

            if !attachedToWord, !rangeBound, !rangeStart, Double(token) != nil {
                numbers.append(token)
            }
        }
        return numbers
    }

    /// Every number in the text, including range bounds.
    private static func allNumbers(in text: String) -> [Double] {
        let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
            Range(match.range, in: text).flatMap { Double(text[$0]) }
        }
    }

    // MARK: - Names

    private static let vocabulary = [
        "cholesterol", "triglycerides", "triglyceride", "glucose", "hemoglobin", "haemoglobin",
        "calculated", "ratio", "total", "pressure", "platelets", "platelet", "creatinine",
        "fasting", "glycated", "normal", "borderline", "abnormal"
    ]
    /// OCR confusions too short for edit-distance matching.
    private static let confusions = ["nan": "non", "n0n": "non"]

    /// Lowercased word tokens with OCR typos corrected against `vocabulary`.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { correctedToken(String($0)) }
    }

    private static func correctedToken(_ token: String) -> String {
        if let fixed = confusions[token] { return fixed }
        guard token.count >= 5, !vocabulary.contains(token), token.allSatisfy(\.isLetter) else { return token }
        let limit = token.count >= 8 ? 2 : 1
        let best = vocabulary
            .map { ($0, editDistance(token, $0)) }
            .filter { $0.1 <= limit }
            .min { $0.1 < $1.1 }
        return best?.0 ?? token
    }

    private static func significantTokens(_ name: String) -> Set<String> {
        let stopWords: Set<String> = ["calculated", "level", "serum", "blood", "test", "the", "of"]
        return Set(tokens(name).filter { $0.count >= 3 && !stopWords.contains($0) })
    }

    private static func normalizedKey(_ name: String) -> String {
        tokens(name).joined(separator: " ")
    }

    private static func isEstimate(_ name: String) -> Bool {
        !Set(tokens(name)).isDisjoint(with: ["risk", "score"])
    }

    /// The model's name with OCR-typo words replaced ("LDL Cholestejol" -> "LDL Cholesterol").
    private static func correctedName(_ name: String) -> String {
        name.split(separator: " ").map { word -> String in
            let lowered = word.lowercased()
            guard lowered.allSatisfy(\.isLetter) else { return String(word) }
            let fixed = correctedToken(lowered)
            return fixed == lowered ? String(word) : fixed.capitalized
        }.joined(separator: " ")
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Values

    /// "115 mg/dL" -> "115", "138 / 89" -> "138/89"; nil when there is no number.
    private static func normalizedValue(_ raw: String) -> String? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        if let pressure = cleaned.range(of: #"\d{2,3}\s*/\s*\d{2,3}"#, options: .regularExpression) {
            return cleaned[pressure].replacingOccurrences(of: " ", with: "")
        }
        guard let number = cleaned.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return String(cleaned[number])
    }

    // MARK: - Reference ranges

    /// A printed reference range: "65-99", "<200", "< 5.7%", ">OR=46", "≤5.0".
    private struct NumericRange {
        var low: Double?
        var high: Double?
        var lowInclusive = true
        var highInclusive = true

        init?(_ text: String) {
            let normalized = text
                .replacingOccurrences(of: "OR=", with: "=", options: .caseInsensitive)
                .replacingOccurrences(of: "≤", with: "<=")
                .replacingOccurrences(of: "≥", with: ">=")
                .replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: " ", with: "")
            if let match = normalized.range(of: #"\d+(?:\.\d+)?-\d+(?:\.\d+)?"#, options: .regularExpression) {
                let bounds = normalized[match].split(separator: "-").compactMap { Double($0) }
                guard bounds.count == 2 else { return nil }
                low = bounds[0]
                high = bounds[1]
            } else if let match = normalized.range(of: #"(<=|>=|<|>)\d+(?:\.\d+)?"#, options: .regularExpression) {
                let expression = normalized[match]
                let op = expression.prefix { "<>=".contains($0) }
                guard let bound = Double(expression.dropFirst(op.count)) else { return nil }
                if op.hasPrefix("<") {
                    high = bound
                    highInclusive = op == "<="
                } else {
                    low = bound
                    lowInclusive = op == ">="
                }
            } else {
                return nil
            }
        }

        func contains(_ value: Double) -> Bool {
            if let low, (lowInclusive ? value < low : value <= low) { return false }
            if let high, (highInclusive ? value > high : value >= high) { return false }
            return true
        }
    }

    /// Standard adult ranges, used when the report shows neither a flag nor a readable range.
    private struct Reference {
        let key: String
        let displayName: String
        let unit: String
        let range: String
        let matches: (Set<String>) -> Bool
        let evaluate: (String) -> HealthStatus

        /// First match wins, so more specific metrics come first (Non-HDL before HDL,
        /// HbA1c before glucose and hemoglobin, every cholesterol subtype before total).
        static func match<S: Sequence>(_ tokens: S) -> Reference? where S.Element == String {
            let set = Set(tokens)
            return all.first { $0.matches(set) }
        }

        private static func numeric(_ value: String, warningAtOrAbove: Double, borderlineAtOrAbove: Double) -> HealthStatus {
            guard let number = Double(value) else { return .normal }
            if number >= warningAtOrAbove { return .warning }
            if number >= borderlineAtOrAbove { return .borderline }
            return .normal
        }

        static let all: [Reference] = [
            Reference(key: "bp", displayName: "Blood Pressure", unit: "mmHg", range: "< 120/80",
                      matches: { $0.contains("pressure") || $0.contains("bp") },
                      evaluate: { value in
                          let parts = value.split(separator: "/").compactMap { Double($0) }
                          guard parts.count == 2 else { return .normal }
                          if parts[0] >= 130 || parts[1] >= 80 { return .warning }
                          if parts[0] >= 120 { return .borderline }
                          return .normal
                      }),
            Reference(key: "hba1c", displayName: "Hemoglobin A1c", unit: "%", range: "< 5.7",
                      matches: { !$0.isDisjoint(with: ["a1c", "hba1c", "glycated", "glycohemoglobin"]) },
                      evaluate: { numeric($0, warningAtOrAbove: 6.5, borderlineAtOrAbove: 5.7) }),
            Reference(key: "glucose", displayName: "Glucose", unit: "mg/dL", range: "< 100",
                      matches: { $0.contains("glucose") || $0.contains("sugar") },
                      evaluate: { numeric($0, warningAtOrAbove: 126, borderlineAtOrAbove: 100) }),
            Reference(key: "chol_hdl_ratio", displayName: "Cholesterol/HDL Ratio", unit: "", range: "≤ 5.0",
                      matches: { $0.contains("ratio") && ($0.contains("hdl") || $0.contains("cholesterol")) },
                      evaluate: { numeric($0, warningAtOrAbove: 5.0001, borderlineAtOrAbove: 5.0001) }),
            Reference(key: "non_hdl", displayName: "Non-HDL Cholesterol", unit: "mg/dL", range: "< 130",
                      matches: { $0.contains("non") && $0.contains("hdl") },
                      evaluate: { numeric($0, warningAtOrAbove: 160, borderlineAtOrAbove: 130) }),
            Reference(key: "ldl", displayName: "LDL Cholesterol", unit: "mg/dL", range: "< 130",
                      matches: { $0.contains("ldl") },
                      evaluate: { numeric($0, warningAtOrAbove: 160, borderlineAtOrAbove: 130) }),
            Reference(key: "hdl", displayName: "HDL Cholesterol", unit: "mg/dL", range: "≥ 40",
                      matches: { $0.contains("hdl") },
                      evaluate: { value in
                          guard let number = Double(value) else { return .normal }
                          return number < 40 ? .borderline : .normal
                      }),
            Reference(key: "triglycerides", displayName: "Triglycerides", unit: "mg/dL", range: "< 150",
                      matches: { !$0.isDisjoint(with: ["triglycerides", "triglyceride", "tg"]) },
                      evaluate: { numeric($0, warningAtOrAbove: 200, borderlineAtOrAbove: 150) }),
            Reference(key: "total_cholesterol", displayName: "Total Cholesterol", unit: "mg/dL", range: "< 200",
                      matches: { $0.contains("cholesterol") },
                      evaluate: { numeric($0, warningAtOrAbove: 240, borderlineAtOrAbove: 200) }),
            Reference(key: "bmi", displayName: "BMI", unit: "", range: "18.5-24",
                      matches: { $0.contains("bmi") || ($0.contains("body") && $0.contains("mass")) },
                      evaluate: { value in
                          guard let number = Double(value) else { return .normal }
                          if number >= 27 { return .warning }
                          if number >= 24 || number < 18.5 { return .borderline }
                          return .normal
                      }),
            Reference(key: "hemoglobin", displayName: "Hemoglobin", unit: "g/dL", range: "13.5-16.5",
                      // "% of total Hgb" is the HbA1c unit, not a hemoglobin result.
                      matches: { !$0.isDisjoint(with: ["hemoglobin", "haemoglobin", "hb"]) || ($0.contains("hgb") && !$0.contains("total")) },
                      evaluate: { value in
                          guard var number = Double(value) else { return .normal }
                          if number > 30 { number /= 10 }   // reported in g/L
                          if number < 12 || number > 17.5 { return .warning }
                          if number < 13.5 || number > 16.5 { return .borderline }
                          return .normal
                      }),
            Reference(key: "platelets", displayName: "Platelets", unit: "10^9/L", range: "150-400",
                      matches: { !$0.isDisjoint(with: ["platelets", "platelet", "plt"]) },
                      evaluate: { value in
                          guard let number = Double(value) else { return .normal }
                          if number < 100 || number > 450 { return .warning }
                          if number < 150 || number > 400 { return .borderline }
                          return .normal
                      })
        ]
    }
}
