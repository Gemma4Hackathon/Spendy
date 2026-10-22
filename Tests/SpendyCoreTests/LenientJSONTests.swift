import Foundation
import Testing
@testable import SpendyCore

/// Structural slips Gemma 4 E2B made on device (bench/results/phase2-diag-2026-10-21.md,
/// phase3-diag) and output that must pass through untouched.
struct LenientJSONTests {

    @Test func validJSONIsUnchanged() {
        let text = #"{"a":"b","list":[1,2],"nested":{"k":"v, \"q\""}}"#
        let result = LenientJSON.parse(text)
        #expect(result.fixes.isEmpty)
        #expect(result.candidate == text)
        #expect(result.dictionary != nil)
    }

    @Test func arrayClosedWithBraceIsSwapped() {
        let result = LenientJSON.parse(#"{"metrics":[{"name":"Glucose"}},"next":1}"#)
        #expect(result.fixes.contains("swap_closer"))
        #expect((result.dictionary?["metrics"] as? [Any])?.count == 1)
    }

    @Test func stringCutByNewlineIsClosed() {
        let result = LenientJSON.parse("{\"a\":\"cut here\n,\"b\":\"ok\"}")
        #expect(result.fixes.contains("close_string"))
        #expect(result.dictionary?["b"] as? String == "ok")
    }

    @Test func newlineInsideProseIsEscaped() {
        let result = LenientJSON.parse("{\"note\":\"## Title\n- item\"}")
        #expect(result.fixes.contains("escape_newline"))
        #expect(result.dictionary?["note"] as? String == "## Title\n- item")
    }

    @Test func missingFinalBraceIsAppended() {
        let result = LenientJSON.parse(#"{"metrics":[{"name":"Glucose","value":"115"}]"#)
        #expect(result.fixes.contains("append_closer"))
        #expect(result.dictionary != nil)
    }

    @Test func trailingCommaIsDropped() {
        let result = LenientJSON.parse(#"{"a":[1,2,],}"#)
        #expect(result.fixes.contains("trailing_comma"))
        #expect((result.dictionary?["a"] as? [Any])?.count == 2)
    }

    @Test func danglingKeyIsDropped() {
        // phase3-diag, IMG_9603 crop: "unit":"%","" then }
        let result = LenientJSON.parse(#"{"metrics":[{"name":"Hemoglobin A1c","value":"6.1","unit":"%",""},{"name":"Glucose","value":"115"}]}"#)
        #expect(result.fixes.contains("dangling_key"))
        let metrics = result.dictionary?["metrics"] as? [[String: Any]]
        #expect(metrics?.count == 2)
        #expect(metrics?.first?["unit"] as? String == "%")
    }

    @Test func fencesAndTrailingProseAreIgnored() {
        let result = LenientJSON.parse("Here you go:\n```json\n{\"a\":1}\n```\nThanks {\"b\":2}")
        #expect(result.dictionary?["a"] as? Int == 1)
        #expect(result.dictionary?["b"] == nil)
    }
}
