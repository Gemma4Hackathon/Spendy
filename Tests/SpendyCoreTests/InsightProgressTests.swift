import Testing
@testable import SpendyCore

/// Prefixes of a real streamed Insights answer (phase3-insights-confirm, shortened).
struct InsightProgressTests {

    private let answer = """
    {"actionPlan":{"movement":{"title":"Increase daily walking","recommendation":"Aim for 30 minutes.","whyItMatters":"May help."},\
    "food":{"title":"Reduce Food Delivery spending","recommendation":"Cap at NT$210 per week.","whyItMatters":"Helps."}},\
    "findings":[{"causeDetail":"Food Delivery is the largest category.","risk":"May contribute to Glucose.",\
    "actions":[{"title":"Cap Food Delivery at NT$210/week","description":"d","expectedOutcome":"Save NT$77 in 7 days"}]},\
    {"causeDetail":"Fast Food adds up.","risk":"May contribute to Hemoglobin A1c.",\
    "actions":[{"title":"Cap Fast Food at NT$70/week","description":"d","expectedOutcome":"Save NT$28 in 7 days"}]}]}
    """

    private func progress(upTo marker: String) -> InsightProgress {
        let end = answer.range(of: marker)!.lowerBound
        return InsightProgress.from(partial: String(answer[..<end]), tokens: 1)
    }

    @Test func nothingFinishedWhileWritingTheFirstSection() {
        let p = progress(upTo: "\"whyItMatters\":\"May help.")
        #expect(p.finished.isEmpty)
        #expect(p.current == .movement)
    }

    @Test func sectionFinishesWhenTheNextOneStarts() {
        let p = progress(upTo: "\"recommendation\":\"Cap at")
        #expect(p.finished[.movement] == "Increase daily walking")
        #expect(p.current == .food)
    }

    @Test func firstFindingFinishesWhenTheSecondStarts() {
        let p = progress(upTo: "\"causeDetail\":\"Fast Food")
        #expect(p.finished[.food] == "Reduce Food Delivery spending")
        #expect(p.finished[.finding1] == "Cap Food Delivery at NT$210/week")
        #expect(p.current == .finding2)
        #expect(!p.isComplete)
    }

    @Test func completeAnswerFinishesEveryStep() {
        let p = InsightProgress.from(partial: answer, tokens: 474)
        #expect(p.current == nil)
        #expect(p.isComplete)
        #expect(p.finished[.finding2] == "Cap Fast Food at NT$70/week")
    }

    @Test func emptyOrProseHasNoProgress() {
        #expect(InsightProgress.from(partial: "", tokens: 0).finished.isEmpty)
        #expect(InsightProgress.from(partial: "Sure, here", tokens: 3).finished.isEmpty)
    }
}
