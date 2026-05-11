import Observation
import Foundation

@Observable
final class AppState {

    // MARK: - Data
    var profile: UserProfile          = .empty
    var spendingEntries: [SpendingEntry] = []
    var healthReport: HealthReport?   = nil
    var insightResult: InsightResult? = nil

    // MARK: - UI / Navigation
    var selectedTab: Int  = 0
    var isDemoLoaded: Bool = false

    // MARK: - Month filter (Optimization 2)
    var selectedMonth: Date = Date()

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

    // MARK: - Month-filtered entries (Optimization 2)
    var filteredEntries: [SpendingEntry] {
        spendingEntries.filter { $0.isInMonth(selectedMonth) }
    }

    var hasHealthData: Bool   { healthReport != nil }
    var hasSpendingData: Bool { !filteredEntries.isEmpty }
    var canGenerateInsights: Bool { hasHealthData && hasSpendingData }

    // MARK: - Month navigation helpers
    var selectedMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy / MM"
        return f.string(from: selectedMonth)
    }

    func stepMonth(by delta: Int) {
        if let moved = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = moved
        }
    }

    var canGoForward: Bool {
        // Don't navigate beyond the current month
        let now = Date()
        let cal = Calendar.current
        return !cal.isDate(selectedMonth, equalTo: now, toGranularity: .month)
    }

    // MARK: - Actions
    func loadDemo() {
        profile         = .demo
        spendingEntries = SpendingEntry.demoEntries
        healthReport    = .demo
        insightResult   = .demo
        isDemoLoaded    = true
        saveToDisk()
    }

    func clearAll() {
        profile              = .empty
        spendingEntries      = []
        healthReport         = nil
        insightResult        = nil
        isDemoLoaded         = false
        healthScanImageData  = nil
        PersistenceManager.shared.delete(fileName: PKey.profile)
        PersistenceManager.shared.delete(fileName: PKey.spending)
        PersistenceManager.shared.delete(fileName: PKey.health)
        PersistenceManager.shared.delete(fileName: PKey.insight)
    }

    func addSpending(_ entry: SpendingEntry) {
        spendingEntries.insert(entry, at: 0)
        PersistenceManager.shared.save(spendingEntries, fileName: PKey.spending)
    }

    func navigateTo(tab: Int) {
        selectedTab = tab
    }

    // MARK: - Persist (manual save for batch updates)
    func saveToDisk() {
        PersistenceManager.shared.save(profile, fileName: PKey.profile)
        PersistenceManager.shared.save(spendingEntries, fileName: PKey.spending)
        if let health = healthReport {
            PersistenceManager.shared.save(health, fileName: PKey.health)
        }
        if let insight = insightResult {
            PersistenceManager.shared.save(insight, fileName: PKey.insight)
        }
    }

    // MARK: - Load from disk
    private func loadFromDisk() {
        if let p: UserProfile = PersistenceManager.shared.load(fileName: PKey.profile) {
            profile = p
        }
        if let s: [SpendingEntry] = PersistenceManager.shared.load(fileName: PKey.spending) {
            spendingEntries = s
            isDemoLoaded = !s.isEmpty
        }
        if let h: HealthReport = PersistenceManager.shared.load(fileName: PKey.health) {
            healthReport = h
        }
        if let i: InsightResult = PersistenceManager.shared.load(fileName: PKey.insight) {
            insightResult = i
        }
    }
}
