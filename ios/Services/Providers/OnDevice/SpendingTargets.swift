import Foundation

/// Weekly spending targets shown in Finance and Insights. Computed in Swift because the
/// on-device model miscalculates them (it suggested NT$765/week for an NT$800 month and
/// called a month of spending a 7-day saving).
nonisolated enum SpendingTargets {
    /// Current weekly pace of a monthly total.
    static func weeklyPace(_ monthlyAmount: Double) -> Int {
        Int(monthlyAmount / 4)
    }

    /// A weekly cap 25 % below the current pace, rounded down to NT$10 (at least NT$10).
    static func weeklyCap(_ monthlyAmount: Double) -> Int {
        max(10, Int(monthlyAmount * 0.75 / 4) / 10 * 10)
    }

    /// "Food Delivery: now about NT$287/week, cap NT$210/week, saves about NT$77/week"
    static func summary(category: String, monthlyAmount: Double) -> String {
        let pace = weeklyPace(monthlyAmount)
        let cap = weeklyCap(monthlyAmount)
        return "\(category): now about NT$\(pace)/week, cap NT$\(cap)/week, saves about NT$\(max(0, pace - cap))/week"
    }
}
