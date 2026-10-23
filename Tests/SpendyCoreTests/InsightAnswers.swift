import Foundation
@testable import SpendyCore

/// Real Gemma 4 Insights answers for the demo month and the screen-photo scan. The Mac ones come
/// from bench/mac_insights, whose answer to the device prompt is byte-identical to the iPhone's.
enum InsightAnswers {

    /// Mac, final prompt: every field is usable as written.
    static let correct = #"""
    {"actionPlan":{"movement":{"title":"Increase daily physical activity","recommendation":"Aim for 150 minutes of moderate activity per week to support overall health."},"food":{"title":"Reduce food delivery spending","recommendation":"Limit Food Delivery spending to the weekly target of NT$210 to save NT$77 per week."}},"findings":[{"risk":"Frequent Food Delivery purchases may contribute to Glucose 115mg/dL due to added sugar, refined carbs, or large portions."},{"risk":"Frequent Fast Food purchases may contribute to Hemoglobin A1c 6.1% of total Hgb due to added sugar, refined carbs, or large portions."}]}
    """#

    /// Mac, first draft of the prompt: the Food Delivery finding talks about sugary drinks.
    static let offTopic = #"""
    {"actionPlan":{"movement":{"title":"Increase daily physical activity","recommendation":"Aim for 150 minutes of movement per week to improve health metrics."},"food":{"title":"Reduce food delivery spending","recommendation":"Limit Food Delivery spending to NT$210 per week to save NT$77 weekly."}},"findings":[{"risk":"Sugary drinks spending may affect Glucose: The high spending on sugary drinks may contribute to the elevated Glucose level of 115mg/dL."},{"risk":"Fast food spending may affect Hemoglobin A1c: The high spending on fast food may contribute to the elevated Hemoglobin A1c of 6.1% of total Hgb."}]}
    """#

    /// Mac, second draft: the movement plan promises better glucose levels.
    static let labPromise = #"""
    {"actionPlan":{"movement":{"title":"Increase daily physical activity","recommendation":"Aim for 30 minutes of walking or light exercise daily to improve glucose levels."},"food":{"title":"Reduce food delivery spending","recommendation":"Limit Food Delivery spending to the weekly target of NT$210 to save NT$77 weekly."}},"findings":[{"risk":"Frequent Food Delivery purchases may contribute to Glucose 115mg/dL due to added sugar or high glycemic load."},{"risk":"Frequent Fast Food purchases may contribute to Hemoglobin A1c 6.1% of total Hgb due to high sodium or unhealthy fats."}]}
    """#

    /// iPhone, phase4-r1: the previous schema (model-written actions); still composes.
    static let previousSchema = #"""
    {"actionPlan":{"movement":{"title":"Increase daily movement","recommendation":"Increase daily walking, jogging, or cycling duration","whyItMatters":"This may help support Glucose and Hemoglobin A1c."},"food":{"title":"Reduce Food Delivery spending","recommendation":"Reduce Food Delivery spending to NT$210/week","whyItMatters":"This helps reduce exposure to high-calorie intake that may contribute to Glucose and Hemoglobin A1c."}},"findings":[{"causeDetail":"Spending NT$1150 on Food Delivery this month indicates a high frequency of ordering meals.","risk":"This spending pattern may contribute to Glucose levels of 115mg/dL.","actions":[{"title":"Limit Food Delivery to NT$210/week","description":"Limit Food Delivery spending to NT$210/week to reduce exposure to high-calorie intake that may contribute to Glucose and Hemoglobin A1c.","expectedOutcome":"Save NT$77 in 7 days"}]},{"causeDetail":"Spending NT$395 on Fast Food this month indicates a high frequency of purchasing fast food.","risk":"This spending pattern may contribute to Hemoglobin A1c of 6.1% of total Hgb.","actions":[{"title":"Limit Fast Food to NT$70/week","description":"Limit Fast Food spending to NT$70/week to reduce exposure to high-calorie intake that may contribute to Hemoglobin A1c.","expectedOutcome":"Save NT$28 in 7 days"}]}]}
    """#

    /// The demo month (bench/README.md).
    static let spending: [SpendingEntry] = [
        (SpendingCategory.foodDelivery, 1150.0), (.entertainment, 800), (.groceries, 520), (.fastFood, 395),
        (.lateNight, 310), (.coffee, 285), (.convenienceStore, 215), (.beverages, 150),
    ].map { SpendingEntry(title: $0.0.rawValue, amount: $0.1, category: $0.0) }

    /// The flagged metrics of the sample report plus two normal ones.
    static let health = HealthReport(metrics: [
        HealthMetric(name: "Glucose", value: "115", unit: "mg/dL", normalRange: "65-99", status: .warning, icon: "", progress: 0),
        HealthMetric(name: "Hemoglobin A1c", value: "6.1", unit: "% of total Hgb", normalRange: "< 5.7", status: .warning, icon: "", progress: 0),
        HealthMetric(name: "Total Cholesterol", value: "164", unit: "mg/dL", normalRange: "125-200", status: .normal, icon: "", progress: 0),
        HealthMetric(name: "HDL Cholesterol", value: "81", unit: "mg/dL", normalRange: ">= 40", status: .normal, icon: "", progress: 0),
    ], reportDate: Date(), labName: "", evidenceTrace: nil)
}
