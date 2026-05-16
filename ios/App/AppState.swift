import Observation
import Foundation

@Observable
final class AppState {

    // MARK: - Data
    var profile: UserProfile          = .empty
    var spendingEntries: [SpendingEntry] = []
    var healthReport: HealthReport?   = nil
    var insightResult: InsightResult? = nil
    var financeSummariesByMonth: [String: FinanceSummary] = [:]
    var insightResultsByMonth: [String: InsightResult] = [:]

    // MARK: - UI / Navigation
    var selectedTab: Int  = 0
    var isDemoLoaded: Bool = false

    // MARK: - Month filters
    var selectedMonth: Date = Date()
    var analysisMonth: Date = SpendingEntry.demoMainMonth

    // MARK: - Processing States
    var isProcessingHealth: Bool     = false
    var isGeneratingInsights: Bool   = false
    var healthScanImageData: Data?   = nil
    var lastInferenceSource: String  = "Mock"

    // MARK: - Persistence keys
    private enum PKey {
        static let profile  = "spendy_profile"
        static let spending = "spendy_spending"
        static let health   = "spendy_health"
        static let insight  = "spendy_insight"
        static let insightResultsByMonth = "spendy_insights_by_month"
        static let financeSummaries = "spendy_finance_summaries"
    }

    // MARK: - Init (auto-load)
    init() { loadFromDisk() }

    // MARK: - Computed: All entries
    var totalMonthlySpent: Double {
        filteredEntries.reduce(0) { $0 + $1.amount }
    }

    var spendingByCategory: [SpendingCategory: Double] {
        filteredEntries.reduce(into: [:]) { dict, entry in
            dict[entry.category, default: 0] += entry.amount
        }
    }

    var topCategory: SpendingCategory? {
        spendingByCategory.max(by: { $0.value < $1.value })?.key
    }

    var analysisTotalSpent: Double {
        analysisEntries.reduce(0) { $0 + $1.amount }
    }

    var analysisSpendingByCategory: [SpendingCategory: Double] {
        analysisEntries.reduce(into: [:]) { dict, entry in
            dict[entry.category, default: 0] += entry.amount
        }
    }

    var analysisTopCategory: SpendingCategory? {
        analysisSpendingByCategory.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Month-filtered entries (Optimization 2)
    var filteredEntries: [SpendingEntry] {
        spendingEntries.filter { $0.isInMonth(selectedMonth) }
    }

    var analysisEntries: [SpendingEntry] {
        spendingEntries.filter { $0.isInMonth(analysisMonth) }
    }

    var hasHealthData: Bool   { healthReport != nil }
    var hasSpendingData: Bool { !filteredEntries.isEmpty }
    var hasAnalysisSpendingData: Bool { !analysisEntries.isEmpty }
    var canGenerateInsights: Bool { hasHealthData && hasAnalysisSpendingData }

    // MARK: - Month navigation helpers
    var selectedMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy / MM"
        return f.string(from: selectedMonth)
    }

    var analysisMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy / MM"
        return f.string(from: analysisMonth)
    }

    func stepMonth(by delta: Int) {
        if let moved = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = moved
        }
    }

    func stepAnalysisMonth(by delta: Int) {
        if let moved = Calendar.current.date(byAdding: .month, value: delta, to: analysisMonth) {
            analysisMonth = moved
            insightResult = insightResult(for: moved)
        }
    }

    var canGoForward: Bool {
        // Don't navigate beyond the current month
        let now = Date()
        let cal = Calendar.current
        return !cal.isDate(selectedMonth, equalTo: now, toGranularity: .month)
    }

    var canGoAnalysisForward: Bool {
        let now = Date()
        let cal = Calendar.current
        return !cal.isDate(analysisMonth, equalTo: now, toGranularity: .month)
    }

    // MARK: - Actions
    func loadDemo() {
        loadFinanceDemo()
    }

    func loadFinanceDemo() {
        profile         = .demo
        spendingEntries = SpendingEntry.demoEntries
        selectedMonth   = SpendingEntry.demoMainMonth
        analysisMonth   = SpendingEntry.demoMainMonth
        healthReport    = nil
        financeSummariesByMonth = [:]
        clearAllInsights()
        isDemoLoaded    = true
        PersistenceManager.shared.save(profile,         fileName: PKey.profile)
        PersistenceManager.shared.save(spendingEntries, fileName: PKey.spending)
        PersistenceManager.shared.save(financeSummariesByMonth, fileName: PKey.financeSummaries)
        PersistenceManager.shared.save(insightResultsByMonth, fileName: PKey.insightResultsByMonth)
        PersistenceManager.shared.delete(fileName: PKey.health)
    }

    func clearAll() {
        profile              = .empty
        spendingEntries      = []
        healthReport         = nil
        insightResult        = nil
        financeSummariesByMonth = [:]
        insightResultsByMonth = [:]
        isDemoLoaded         = false
        selectedMonth        = Date()
        analysisMonth        = SpendingEntry.demoMainMonth
        healthScanImageData  = nil
        PersistenceManager.shared.delete(fileName: PKey.profile)
        PersistenceManager.shared.delete(fileName: PKey.spending)
        PersistenceManager.shared.delete(fileName: PKey.health)
        PersistenceManager.shared.delete(fileName: PKey.insight)
        PersistenceManager.shared.delete(fileName: PKey.insightResultsByMonth)
        PersistenceManager.shared.delete(fileName: PKey.financeSummaries)
    }

    func addSpending(_ entry: SpendingEntry) {
        spendingEntries.insert(entry, at: 0)
        clearFinanceSummary(for: entry.date)
        clearInsight(for: entry.date)
        PersistenceManager.shared.save(spendingEntries, fileName: PKey.spending)
    }

    func setHealthReport(_ report: HealthReport?) {
        healthReport = report
        clearAllInsights()
        if let report {
            PersistenceManager.shared.save(report, fileName: PKey.health)
        } else {
            PersistenceManager.shared.delete(fileName: PKey.health)
        }
    }

    func clearInsight() {
        clearInsight(for: analysisMonth)
    }

    func insightResult(for date: Date) -> InsightResult? {
        insightResultsByMonth[monthKey(for: date)]
    }

    func setInsightResult(_ result: InsightResult, for date: Date) {
        let key = monthKey(for: date)
        insightResultsByMonth[key] = result
        if key == monthKey(for: analysisMonth) {
            insightResult = result
        }
        PersistenceManager.shared.save(insightResultsByMonth, fileName: PKey.insightResultsByMonth)
        PersistenceManager.shared.delete(fileName: PKey.insight)
    }

    func clearInsight(for date: Date) {
        let key = monthKey(for: date)
        insightResultsByMonth.removeValue(forKey: key)
        if key == monthKey(for: analysisMonth) {
            insightResult = nil
        }
        PersistenceManager.shared.save(insightResultsByMonth, fileName: PKey.insightResultsByMonth)
        PersistenceManager.shared.delete(fileName: PKey.insight)
    }

    func clearAllInsights() {
        insightResult = nil
        insightResultsByMonth = [:]
        PersistenceManager.shared.save(insightResultsByMonth, fileName: PKey.insightResultsByMonth)
        PersistenceManager.shared.delete(fileName: PKey.insight)
    }

    func financeSummary(for date: Date) -> FinanceSummary? {
        financeSummariesByMonth[monthKey(for: date)]
    }

    func setFinanceSummary(_ summary: FinanceSummary, for date: Date) {
        financeSummariesByMonth[monthKey(for: date)] = summary
        PersistenceManager.shared.save(financeSummariesByMonth, fileName: PKey.financeSummaries)
    }

    func clearFinanceSummary(for date: Date) {
        financeSummariesByMonth.removeValue(forKey: monthKey(for: date))
        PersistenceManager.shared.save(financeSummariesByMonth, fileName: PKey.financeSummaries)
    }

    func navigateTo(tab: Int) {
        selectedTab = tab
    }

    // MARK: - Persist (manual save for batch updates)
    func saveToDisk() {
        PersistenceManager.shared.save(profile, fileName: PKey.profile)
        PersistenceManager.shared.save(spendingEntries, fileName: PKey.spending)
        PersistenceManager.shared.save(financeSummariesByMonth, fileName: PKey.financeSummaries)
        PersistenceManager.shared.save(insightResultsByMonth, fileName: PKey.insightResultsByMonth)
        if let health = healthReport {
            PersistenceManager.shared.save(health, fileName: PKey.health)
        }
        PersistenceManager.shared.delete(fileName: PKey.insight)
    }

    // MARK: - Load from disk
    private func loadFromDisk() {
        if let p: UserProfile = PersistenceManager.shared.load(fileName: PKey.profile) {
            profile = p
        }
        if let s: [SpendingEntry] = PersistenceManager.shared.load(fileName: PKey.spending) {
            spendingEntries = s
            isDemoLoaded = !s.isEmpty
            refreshLegacyFinanceDemoIfNeeded()
        }
        if let summaries: [String: FinanceSummary] = PersistenceManager.shared.load(fileName: PKey.financeSummaries) {
            financeSummariesByMonth = summaries
        }
        if let insights: [String: InsightResult] = PersistenceManager.shared.load(fileName: PKey.insightResultsByMonth) {
            insightResultsByMonth = insights
        }
        if let h: HealthReport = PersistenceManager.shared.load(fileName: PKey.health) {
            healthReport = h
        }
        PersistenceManager.shared.delete(fileName: PKey.insight)
        insightResult = insightResult(for: analysisMonth)
    }

    private func refreshLegacyFinanceDemoIfNeeded() {
        guard profile.name == UserProfile.demo.name else { return }

        let calendar = Calendar.current
        let months = Set(spendingEntries.map { calendar.component(.month, from: $0.date) })
        let hasFullDemoRange = [1, 2, 3, 4, 5].allSatisfy { months.contains($0) }
        guard !hasFullDemoRange else { return }

        spendingEntries = SpendingEntry.demoEntries
        selectedMonth = SpendingEntry.demoMainMonth
        analysisMonth = SpendingEntry.demoMainMonth
        financeSummariesByMonth = [:]
        clearAllInsights()
        PersistenceManager.shared.save(spendingEntries, fileName: PKey.spending)
        PersistenceManager.shared.save(financeSummariesByMonth, fileName: PKey.financeSummaries)
    }

    private func monthKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
