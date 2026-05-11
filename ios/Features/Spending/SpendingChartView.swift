import SwiftUI
import Charts

// MARK: - Daily spending data point for Charts
struct DailySpend: Identifiable {
    let id = UUID()
    let day: Date
    let amount: Double
    let category: SpendingCategory
}

struct SpendingChartView: View {
    let entries: [SpendingEntry]

    private var dailyData: [DailySpend] {
        var dict: [String: [SpendingCategory: Double]] = [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for e in entries {
            let key = fmt.string(from: e.date)
            dict[key, default: [:]][e.category, default: 0] += e.amount
        }
        return dict.flatMap { (key, catAmounts) -> [DailySpend] in
            let day = fmt.date(from: key) ?? Date()
            return catAmounts.map { DailySpend(day: day, amount: $0.value, category: $0.key) }
        }.sorted { $0.day < $1.day }
    }

    var body: some View {
        if dailyData.isEmpty {
            Text("No data for this month")
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
                .frame(maxWidth: .infinity, minHeight: 130)
        } else {
            Chart(dailyData) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("NT$", point.amount)
                )
                .foregroundStyle(Color(hex: point.category.colorHex).opacity(0.85))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel(format: .dateTime.day())
                        .foregroundStyle(SpendyTheme.textMuted)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .foregroundStyle(SpendyTheme.textMuted)
                        .font(.caption2)
                }
            }
            .frame(height: 130)
        }
    }
}
