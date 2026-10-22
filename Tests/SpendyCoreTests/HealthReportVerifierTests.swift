import Testing
@testable import SpendyCore

/// Ground truth for the sample report (bench/README.md, section 6).
private let truth: [String: (value: String, status: HealthStatus)] = [
    "glucose": ("115", .warning), "hba1c": ("6.1", .warning),
    "total_cholesterol": ("164", .normal), "hdl": ("81", .normal), "triglycerides": ("45", .normal),
    "ldl": ("74", .normal), "non_hdl": ("83", .normal), "chol_hdl_ratio": ("2.0", .normal),
]

private let fixtures: [String: [OCRLine]] = [
    "flatScanPhase2": Fixtures.flatScanPhase2, "flatScanPhase3": Fixtures.flatScanPhase3, "screenPhoto": Fixtures.screenPhoto,
]

private func tableMetrics(_ lines: [OCRLine]) -> [VerifiedMetric] {
    HealthReportVerifier.verify(HealthReportVerifier.tableCandidates(lines: lines), lines: lines, requireSameRow: true)
}

private func correct(_ metrics: [VerifiedMetric]) -> Set<String> {
    Set(metrics.filter { m in truth[m.key].map { $0.value == m.value && $0.status == m.status } ?? false }.map(\.key))
}

struct HealthReportVerifierTests {

    @Test(arguments: ["flatScanPhase3", "screenPhoto"])
    func tableRowsReadAllEightValues(name: String) {
        let metrics = tableMetrics(fixtures[name]!)
        #expect(correct(metrics) == Set(truth.keys), "\(name)")
        #expect(metrics.allSatisfy { truth[$0.key] != nil }, "\(name): no metric outside the report table")
    }

    @Test func misreadRatioIsDroppedNotShown() {
        // Phases 1-2 export of IMG_9603: OCR reads the ratio "2.0" as "20".
        let metrics = tableMetrics(Fixtures.flatScanPhase2)
        #expect(correct(metrics) == Set(truth.keys).subtracting(["chol_hdl_ratio"]))
        #expect(!metrics.contains { $0.key == "chol_hdl_ratio" })
    }

    @Test func modelValueOutsidePlausibleRangeIsRejected() {
        let candidate = MetricCandidate(name: "Cholesterol/HDL Ratio (Calculated)", value: "20", unit: "", normalRange: "", modelStatus: .normal)
        #expect(HealthReportVerifier.verify([candidate], lines: Fixtures.flatScanPhase2, requireSameRow: false).isEmpty)
    }

    @Test(arguments: ["flatScanPhase2", "flatScanPhase3", "screenPhoto"])
    func hbA1cUnitIsNotHemoglobin(name: String) {
        let lines = fixtures[name]!
        // "6.1% of total Hgb" sits beside "115 mg/dL" in the Key Findings box.
        #expect(!tableMetrics(lines).contains { $0.key == "hemoglobin" })
        let candidate = MetricCandidate(name: "Hemoglobin", value: "115", unit: "g/dL", normalRange: "", modelStatus: nil)
        #expect(HealthReportVerifier.verify([candidate], lines: lines, requireSameRow: true).isEmpty)
    }

    @Test func flagComesFromTheReportRow() {
        let candidate = MetricCandidate(name: "Hemoglobin A1c", value: "6.1", unit: "% of total Hgb", normalRange: "", modelStatus: .normal)
        let metric = HealthReportVerifier.verify([candidate], lines: Fixtures.flatScanPhase3, requireSameRow: false).first
        #expect(metric?.key == "hba1c")
        #expect(metric?.status == .warning)
        #expect(metric?.statusBasis == .reportFlag)
    }

    @Test func ocrTyposStillMatchTheirMetric() {
        // "Nan-HDL" (flat scan) and "ChUlesterol" (screen photo) are Non-HDL Cholesterol, not HDL.
        for lines in [Fixtures.flatScanPhase3, Fixtures.screenPhoto] {
            let metrics = tableMetrics(lines)
            #expect(metrics.first { $0.key == "non_hdl" }?.value == "83")
            #expect(metrics.first { $0.key == "hdl" }?.value == "81")
        }
    }

    @Test func valueNotOnTheReportIsRejected() {
        let invented = MetricCandidate(name: "LDL Cholesterol", value: "140", unit: "mg/dL", normalRange: "< 130", modelStatus: .borderline)
        #expect(HealthReportVerifier.verify([invented], lines: Fixtures.flatScanPhase3, requireSameRow: false).isEmpty)
    }

    @Test func standaloneNumbersSkipRangeBounds() {
        #expect(HealthReportVerifier.standaloneNumbers(in: "65-99 mg/dL: See Note 1") == [1])
        #expect(HealthReportVerifier.standaloneNumbers(in: "< 150 mg/dL") == [])
        #expect(HealthReportVerifier.standaloneNumbers(in: "Result: 6.1% of total Hgb") == [6.1])
    }
}
