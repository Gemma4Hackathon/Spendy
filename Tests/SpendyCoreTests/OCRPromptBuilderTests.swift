import Testing
@testable import SpendyCore

struct OCRPromptBuilderTests {

    private func consumedRows(_ lines: [OCRLine]) -> Set<Int> {
        let readings = HealthReportVerifier.tableReadings(lines: lines)
        let verified = HealthReportVerifier.verify(readings.map(\.candidate), lines: lines, requireSameRow: true)
        return Set(readings.filter { r in verified.contains { $0.name == r.candidate.name && $0.value == r.candidate.value } }
            .flatMap(\.lineIndices))
    }

    @Test func tableRowsFlagsAndRangesAreLeftOut() {
        let lines = Fixtures.flatScanPhase3
        let input = OCRPromptBuilder.modelInput(lines: lines, consumed: consumedRows(lines))
        let kept = input.text.components(separatedBy: "\n")
        #expect(input.text.count * 2 < lines.map(\.text).joined(separator: "\n").count, "at least half shorter")
        for gone in ["164 mg/dL", "81 mg/dL", "Total Cholesterol", "Normal", "Flag", "< 150 mg/dL", "125-200 mg/dL", "5.7-6.4"] {
            #expect(!kept.contains(gone), "\(gone)")
        }
        // Values Swift cannot read from the table stay for Gemma 4.
        for stays in ["8-Year Diabetes", "7%", "BMI", "25.7"] {
            #expect(kept.contains(stays), "\(stays)")
        }
        #expect(kept.count == Set(kept).count, "no repeated lines")
    }

    @Test func patientDetailsAreLeftOut() {
        let lines = [
            OCRLine(text: "Name:", midY: 0.874, height: 0.009),
            OCRLine(text: "TEST, PATIENT", midY: 0.873, height: 0.013),
            OCRLine(text: "DOB:", midY: 0.861, height: 0.009),
            OCRLine(text: "01/01/1969", midY: 0.861, height: 0.009),
            OCRLine(text: "Glucose", midY: 0.416, height: 0.009),
            OCRLine(text: "115 mg/dL", midY: 0.419, height: 0.009),
        ]
        let input = OCRPromptBuilder.modelInput(lines: lines, consumed: [])
        #expect(input.text == "Glucose\n115 mg/dL")
    }

    @Test func fullyReadTableLeavesNothingToStructure() {
        let lines = [
            OCRLine(text: "Glucose", midY: 0.416, height: 0.009),
            OCRLine(text: "115 mg/dL", midY: 0.419, height: 0.009),
            OCRLine(text: "High", midY: 0.419, height: 0.012),
            OCRLine(text: "65-99 mg/dL: See Note 1", midY: 0.421, height: 0.012),
        ]
        #expect(!OCRPromptBuilder.modelInput(lines: lines, consumed: [0, 1]).hasNumbers)
    }
}
