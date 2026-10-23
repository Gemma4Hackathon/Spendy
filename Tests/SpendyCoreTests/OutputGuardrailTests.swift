import Testing
@testable import SpendyCore

/// Sentences the on-device model actually wrote (phase 3 diag and rounds) for the demo spending:
/// Food Delivery 1150, Entertainment 800, Groceries 520, Fast Food 395, Late Night 310,
/// Coffee 285, Convenience Store 215, Sugary Drinks 150; total 3825.
struct OutputGuardrailTests {

    private let context = OutputGuardrail.Context(monthlyByCategory: [
        "Food Delivery": 1150, "Entertainment": 800, "Groceries": 520, "Fast Food": 395,
        "Late Night": 310, "Coffee": 285, "Convenience Store": 215, "Sugary Drinks": 150,
    ], extra: [3825, 1721])

    @Test(arguments: [
        ("Cap Entertainment at NT$765/week, maximum one entertainment outing per week.", OutputGuardrail.Violation.unknownAmount),
        ("The user is spending NT$1150 on Food Delivery weekly.", .monthlyAsWeekly),
        ("Save NT$1150 in 7 days.", .monthlyAsWeekly),
        ("Limit fast food to zero.", .zeroTarget),
        ("Reduce coffee spending to zero.", .zeroTarget),
        ("Reduce Food Delivery spending by NT$1150 to improve cash flow.", .zeroTarget),
        ("Cap Sugary Drinks spending at NT$150 per week.", .monthlyAsWeekly),
        // Phase 4 Finance checklist: NT$210 is the Food Delivery cap; Late Night is about NT$77/week.
        ("Limit Late Night spending to NT$210 per week.", .wrongCategory),
        ("Late-night eating causes high blood sugar.", .causalClaim),
        ("Frequent fast food leads to a higher Hemoglobin A1c.", .causalClaim),
    ])
    func catchesWhatTheModelGotWrong(text: String, expected: OutputGuardrail.Violation) {
        #expect(OutputGuardrail.check(text, context: context).contains(expected), "\(text)")
    }

    @Test func catchesLabPromisesInOutcomes() {
        let text = "In 7 days, you will see a noticeable improvement in your Glucose levels."
        #expect(OutputGuardrail.check(text, context: context, isOutcome: true) == [.labPromise])
        #expect(OutputGuardrail.check(text, context: context, isOutcome: false).isEmpty)
    }

    @Test(arguments: [
        "Cap Food Delivery spending at NT$210 per week.",
        "Save NT$77 in 7 days",
        "Total spending is NT$3825, with Food Delivery at 30% and Entertainment at 20%.",
        "Limit Food Delivery to NT$210 per week by reducing delivery frequency.",
        "Food Delivery is NT$1150 this month, about NT$287 per week.",
        "Swap one sugary drink for a zero-sugar option.",
        "Reduce Late Night spending to NT$50/week to reduce exposure to high-calorie intake.",
        "Cut Fast Food spending to NT$70/week to reduce exposure to high-calorie intake that may contribute to Hemoglobin A1c.",
        "This may help support Glucose and Hemoglobin A1c levels.",
        "Frequent Food Delivery purchases may contribute to Glucose 115mg/dL due to added sugar, refined carbs, or large portions.",
        "Eating late can lead to higher blood sugar the next morning.",
    ])
    func acceptsCorrectSentences(text: String) {
        #expect(OutputGuardrail.check(text, context: context, isOutcome: true).isEmpty, "\(text)")
    }
}
