import Foundation

// MARK: - OCRPromptBuilder
// The OCR text given to Gemma 4 for structuring. A health scan is prefill-bound (TTFT 13-17 s
// of 20-24 s in phase 3), so lines the model does not need are left out: rows Swift already
// read from the table, flag and reference-range columns (decided in HealthReportVerifier),
// patient and specimen details, repeated lines and prose without numbers. Keeping patient
// details out of the prompt is also data minimization.

nonisolated enum OCRPromptBuilder {

    struct Input {
        let text: String
        let keptLines: Int
        let totalLines: Int

        /// Nothing left that could hold a value, e.g. a cropped table Swift read completely.
        var hasNumbers: Bool { text.contains(where: \.isNumber) }
    }

    /// `consumed`: indices of lines whose metric was already read and verified from the table.
    static func modelInput(lines: [OCRLine], consumed: Set<Int>) -> Input {
        let personal = personalRows(lines)
        var seen = Set<String>()
        var kept: [String] = []
        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !consumed.contains(index),
                  !personal.contains(index),
                  !isColumnWord(text),
                  !startsWithRange(text),
                  !isProse(text),
                  seen.insert(text).inserted
            else { continue }
            kept.append(text)
        }
        return Input(text: kept.joined(separator: "\n"), keptLines: kept.count, totalLines: lines.count)
    }

    /// Lines that start with a patient or specimen label, plus the values on the same row.
    private static func personalRows(_ lines: [OCRLine]) -> Set<Int> {
        let labels = ["name:", "dob:", "date of birth", "age:", "gender:", "sex:", "fasting:", "patient id", "phone:",
                      "address:", "specimen:", "requisition:", "collected:", "received:", "reported:",
                      "client #:", "client name:", "department:", "lab:", "lab code"]
        var rows = Set<Int>()
        for label in lines where labels.contains(where: label.text.lowercased().hasPrefix) {
            for (index, line) in lines.enumerated()
            where abs(line.midY - label.midY) < 0.6 * max(line.height, label.height) {
                rows.insert(index)
            }
        }
        return rows
    }

    /// Flag and header words of a results table; status is read from the report in Swift.
    private static func isColumnWord(_ text: String) -> Bool {
        ["normal", "high", "low", "borderline", "abnormal", "flag", "result", "test name"].contains(text.lowercased())
            || text.lowercased().hasPrefix("reference range")
    }

    /// "< 150 mg/dL", "≥126", "65-99 mg/dL: See Note 1", "5.7-6.4"; but not "8-Year Diabetes".
    private static func startsWithRange(_ text: String) -> Bool {
        text.range(of: #"^([<>≤≥]|\d+(\.\d+)?\s*[-–]\s*\d)"#, options: .regularExpression) != nil
    }

    /// Long sentences without numbers (interpretation, notes) carry no metric value.
    private static func isProse(_ text: String) -> Bool {
        text.count > 40 && !text.contains(where: \.isNumber)
    }
}
