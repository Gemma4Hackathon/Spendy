import Testing
@testable import SpendyCore

struct SpendingTargetsTests {

    @Test(arguments: [40.0, 150, 285, 395, 800, 1150, 12_000])
    func capNeverExceedsCurrentPace(monthly: Double) {
        let pace = SpendingTargets.weeklyPace(monthly)
        let cap = SpendingTargets.weeklyCap(monthly)
        #expect(cap > 0)
        #expect(cap <= max(pace, 10))
        if pace >= 20 { #expect(cap < pace) }
    }

    @Test func summaryUsesWeeklyNumbers() {
        #expect(SpendingTargets.summary(category: "Food Delivery", monthlyAmount: 1150)
                == "Food Delivery: now about NT$287/week, cap NT$210/week, saves about NT$77/week")
    }
}
