import Testing
@testable import SpendyCore

struct InsightComposerTests {

    private let context = InsightContext(spending: InsightAnswers.spending, health: InsightAnswers.health)

    private func compose(_ json: String) -> (result: InsightResult, audit: OutputGuardrail.Audit)? {
        InsightComposer.compose(LenientJSON.parse(json).dictionary ?? [:], context: context, health: InsightAnswers.health)
    }

    @Test func modelWordingIsKeptAndSwiftWritesTheNumbers() throws {
        let (result, audit) = try #require(compose(InsightAnswers.correct))
        #expect(audit.checked == 4)
        #expect(audit.replaced == 0)
        #expect(result.actionPlan?.movement.title == "Increase daily physical activity")
        #expect(result.keyFindings[0].risk.hasPrefix("Frequent Food Delivery purchases may contribute"))
        #expect(result.keyFindings[0].causeDetail == "Food Delivery spending was NT$1150 this month, about NT$287 a week.")
        #expect(result.keyFindings[0].actions.map(\.title) == ["Cap Food Delivery at NT$210/week", "Cook or pack lunch on 2 days"])
        #expect(result.keyFindings[1].actions.first?.expectedOutcome == "Save about NT$28 in 7 days.")
    }

    @Test func riskAboutAnotherCategoryIsReplaced() throws {
        let (result, audit) = try #require(compose(InsightAnswers.offTopic))
        #expect(result.keyFindings[0].risk == "This spending pattern may contribute to Glucose.")
        #expect(result.keyFindings[1].risk.hasPrefix("Fast food spending may affect"))
        #expect(audit.summary.contains("off_topic"))
    }

    @Test func labPromiseInThePlanIsReplaced() throws {
        let (result, audit) = try #require(compose(InsightAnswers.labPromise))
        #expect(result.actionPlan?.movement.title == "Walk or jog 25 minutes daily")
        #expect(result.actionPlan?.food.title == "Reduce food delivery spending")
        #expect(audit.summary.contains("lab_promise"))
    }

    @Test func previousSchemaAnswerStillComposes() throws {
        let (result, audit) = try #require(compose(InsightAnswers.previousSchema))
        #expect(audit.replaced == 0)
        #expect(result.keyFindings[1].risk == "This spending pattern may contribute to Hemoglobin A1c of 6.1% of total Hgb.")
        #expect(result.keyFindings[1].actions.first?.title == "Cap Fast Food at NT$70/week")
    }

    @Test(arguments: [
        "{}",
        "Sure, here is the plan.",
        #"{"actionPlan":{"movement":{"title":"REPLACE movement title","recommendation":"REPLACE daily minutes"}},"findings":[{"risk":"REPLACE why"}]}"#,
    ])
    func answerWithoutAModelFieldIsRetried(json: String) {
        #expect(compose(json) == nil)
    }

    /// Every sentence Swift writes must pass the checks applied to the model, for any amount:
    /// no NT$0, no cap above the current pace, no other category's amount.
    @Test(arguments: SpendingCategory.allCases)
    func swiftTextPassesTheGuardrail(category: SpendingCategory) {
        for monthly in Array(stride(from: 10, through: 5000, by: 7)) + [40, 53, 80, 1150] {
            let guardrail = OutputGuardrail.Context(monthlyByCategory: [category.rawValue: monthly])
            let actions = InsightTemplates.actions(category: category.rawValue, monthly: monthly)
            let texts = [InsightTemplates.causeDetail(category: category.rawValue, monthly: monthly)]
                + actions.flatMap { [$0.title, $0.description] }
            for text in texts {
                #expect(OutputGuardrail.check(text, context: guardrail).isEmpty, "\(monthly): \(text)")
            }
            for action in actions {
                #expect(OutputGuardrail.check(action.expectedOutcome, context: guardrail, isOutcome: true).isEmpty, "\(monthly): \(action.expectedOutcome)")
            }
            #expect(actions.count == 2)
        }
    }

    @Test func riskReasonsFitTheMetric() {
        #expect(InsightPrompt.likelyReasons(for: "Hemoglobin A1c").contains("refined carbs"))
        #expect(!InsightPrompt.likelyReasons(for: "Hemoglobin A1c").contains("salt"))
        #expect(InsightPrompt.likelyReasons(for: "LDL Cholesterol").contains("fried food"))
        #expect(InsightPrompt.likelyReasons(for: "Blood Pressure: 130/85").contains("salt"))
    }
}
