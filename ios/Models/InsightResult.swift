import Foundation

// MARK: - Action Item
struct InsightAction: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var description: String
    var expectedOutcome: String
    var timeframe: String
    var difficulty: Int   // 1–3
}

// MARK: - Connection (Cause → Health Impact)
struct InsightConnection: Identifiable, Codable {
    var id: UUID = UUID()
    var icon: String        // SF Symbol name
    var cause: String
    var causeDetail: String
    var healthImpact: String
    var healthDetail: String
    var risk: String
    var accentColor: String // "red", "amber", "blue"
    var actions: [InsightAction]
}

// MARK: - Final Result
struct InsightResult: Codable {
    var keyFindings: [InsightConnection]
    var overallRiskScore: Int        // 0–100
    var monthlySpendingAtRisk: Double
    var generatedAt: Date

    // MARK: Demo Data
    static let demo = InsightResult(
        keyFindings: [
            InsightConnection(
                icon: "cup.and.saucer.fill",
                cause: "High-Sugar Drink Consumption",
                causeDetail: "NT$645 spent on bubble tea in the past 30 days — averaging 1.2 drinks/day, mostly full-sugar, exceeding WHO daily sugar guidelines.",
                healthImpact: "Elevated Blood Sugar",
                healthDetail: "Fasting glucose at 112 mg/dL (normal < 100). HbA1c at 6.1% (prediabetes threshold: 5.7%).",
                risk: "Sustained for 6 months, insulin resistance risk rises ~40%, significantly increasing prediabetes probability.",
                accentColor: "amber",
                actions: [
                    InsightAction(title: "Switch to zero or low sugar",    description: "Reducing sugar per drink saves 200–400 kcal",         expectedOutcome: "Blood glucose may normalize within 3 months", timeframe: "3 months",   difficulty: 2),
                    InsightAction(title: "Limit to 3 drinks per week",     description: "Set a reminder to track intake",                      expectedOutcome: "Saves NT$430/month, reduces sugar by 65%",    timeframe: "Start now",  difficulty: 2),
                ]
            ),
            InsightConnection(
                icon: "moon.fill",
                cause: "Late-Night Delivery Habit",
                causeDetail: "Food delivery accounts for 43% of total spending. Orders cluster between 21:30–23:00, mostly high-fat, high-calorie meals.",
                healthImpact: "Elevated Cholesterol + Metabolism",
                healthDetail: "LDL at 145 mg/dL (high). Triglycerides at 198 mg/dL (high). BMI 25.8 (overweight).",
                risk: "Late-night eating reduces fat metabolism efficiency by ~30%, significantly raising cardiovascular risk.",
                accentColor: "red",
                actions: [
                    InsightAction(title: "Move dinner before 7 PM",        description: "Gives your body 3+ hours to metabolize before sleep",  expectedOutcome: "Triglycerides may drop ~15% within 1 month",  timeframe: "1 month",    difficulty: 2),
                    InsightAction(title: "Cap delivery at NT$1,500/month", description: "Redirect NT$800+ savings to a health fund",           expectedOutcome: "Lower caloric intake + improved finances",     timeframe: "Start now",  difficulty: 1),
                ]
            ),
            InsightConnection(
                icon: "mug.fill",
                cause: "Caffeine Dependency Cycle",
                causeDetail: "NT$825/week on coffee, concentrated between 13:00–17:00 — a sign of low afternoon energy creating a dependency loop.",
                healthImpact: "Elevated Blood Pressure + Poor Sleep",
                healthDetail: "Blood pressure at 138/89 mmHg (high, normal < 120/80). Fatigue pattern closely correlates with caffeine dependency.",
                risk: "Long-term caffeine dependency continuously degrades sleep quality, worsening fatigue in a vicious cycle — blood pressure remains elevated.",
                accentColor: "blue",
                actions: [
                    InsightAction(title: "No caffeine after 2 PM",         description: "Avoid disrupting your circadian rhythm",              expectedOutcome: "Sleep depth improves in 2 weeks; BP stabilizes", timeframe: "2 weeks",  difficulty: 3),
                    InsightAction(title: "Replace coffee with a walk",      description: "15 min walk boosts alertness for 2–3 hours",         expectedOutcome: "Blood pressure may drop 5–8 mmHg",             timeframe: "1 month",  difficulty: 2),
                ]
            ),
        ],
        overallRiskScore: 68,
        monthlySpendingAtRisk: 3200,
        generatedAt: Date()
    )
}
