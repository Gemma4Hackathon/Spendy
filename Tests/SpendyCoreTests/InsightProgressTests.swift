import Testing
@testable import SpendyCore

/// Prefixes of a real streamed Insights answer (InsightAnswers.correct).
struct InsightProgressTests {

    private let answer = InsightAnswers.correct.trimmingCharacters(in: .whitespacesAndNewlines)

    private func progress(upTo marker: String) -> InsightProgress {
        let end = answer.range(of: marker)!.lowerBound
        return InsightProgress.from(partial: String(answer[..<end]), tokens: 1)
    }

    @Test func nothingFinishedWhileWritingTheFirstSection() {
        let p = progress(upTo: "\"recommendation\":\"Aim for")
        #expect(p.finished.isEmpty)
        #expect(p.current == .movement)
    }

    @Test func sectionFinishesWhenTheNextOneStarts() {
        let p = progress(upTo: "\"recommendation\":\"Limit Food")
        #expect(p.finished[.movement] == "Increase daily physical activity")
        #expect(p.current == .food)
    }

    @Test func firstFindingFinishesWhenTheSecondStarts() {
        let p = progress(upTo: "\"risk\":\"Frequent Fast Food")
        #expect(p.finished[.food] == "Reduce food delivery spending")
        #expect(p.finished[.finding1] == "")
        #expect(p.current == .finding2)
        #expect(!p.isComplete)
    }

    @Test func completeAnswerFinishesEveryStep() {
        let p = InsightProgress.from(partial: answer, tokens: 182)
        #expect(p.current == nil)
        #expect(p.isComplete)
        #expect(p.finished[.finding2] == "")
    }

    @Test func emptyOrProseHasNoProgress() {
        #expect(InsightProgress.from(partial: "", tokens: 0).finished.isEmpty)
        #expect(InsightProgress.from(partial: "Sure, here", tokens: 3).finished.isEmpty)
    }
}
