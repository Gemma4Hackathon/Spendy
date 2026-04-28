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

    // MARK: - Processing States
    var isProcessingHealth: Bool     = false
    var isGeneratingInsights: Bool   = false
    var healthScanImageData: Data?   = nil
    var lastInferenceSource: String  = "Mock"

    // MARK: - Computed
    var totalMonthlySpent: Double {
        spendingEntries.reduce(0) { $0 + $1.amount }
    }

    var spendingByCategory: [SpendingCategory: Double] {
        spendingEntries.reduce(into: [:]) { dict, entry in
            dict[entry.category, default: 0] += entry.amount
        }
    }

    var topCategory: SpendingCategory? {
        spendingByCategory.max(by: { $0.value < $1.value })?.key
    }

    var hasHealthData: Bool   { healthReport != nil }
    var hasSpendingData: Bool { !spendingEntries.isEmpty }
    var canGenerateInsights: Bool { hasHealthData && hasSpendingData }

    // MARK: - Actions
    func loadDemo() {
        profile         = .demo
        spendingEntries = SpendingEntry.demoEntries
        healthReport    = .demo
        insightResult   = .demo
        isDemoLoaded    = true
    }

    func clearAll() {
        profile              = .empty
        spendingEntries      = []
        healthReport         = nil
        insightResult        = nil
        isDemoLoaded         = false
        healthScanImageData  = nil
    }

    func addSpending(_ entry: SpendingEntry) {
        spendingEntries.insert(entry, at: 0)
    }

    func navigateTo(tab: Int) {
        selectedTab = tab
    }
}
