import SwiftUI

struct HealthResultsView: View {
    @Environment(AppState.self) var appState
    @State private var appeared = false

    var body: some View {
        ZStack {
            SpendyTheme.background.ignoresSafeArea()
            if let report = appState.healthReport {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SpendyTheme.spacing) {
                        summaryBanner(report)
                        metricsGrid(report)
                    }
                    .padding(.horizontal, SpendyTheme.padding)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }
                // Sticky CTA
                VStack {
                    Spacer()
                    ctaButton(report)
                        .padding(.horizontal, SpendyTheme.padding)
                        .padding(.bottom, 32)
                        .padding(.top, 20)
                        .background(SpendyTheme.background)
                }
            } else {
                Text("No health data").foregroundStyle(SpendyTheme.textMuted)
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Banner
    private func summaryBanner(_ report: HealthReport) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(report.warningCount > 0 ? SpendyTheme.healthBad.opacity(0.12) : SpendyTheme.healthOK.opacity(0.12))
                Image(systemName: report.warningCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(report.warningCount > 0 ? SpendyTheme.healthBad : SpendyTheme.healthOK)
                    .font(.title2)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(report.abnormalCount) metrics need attention")
                    .font(.headline).fontWeight(.semibold).foregroundStyle(.white)
                Text("Report date: \(formattedDate(report.reportDate))  ·  \(report.labName)")
                    .font(.caption).foregroundStyle(SpendyTheme.textMuted)
            }
            Spacer()
        }
        .padding(SpendyTheme.padding)
        .background(
            report.warningCount > 0
            ? SpendyTheme.healthBad.opacity(0.07)
            : SpendyTheme.healthOK.opacity(0.07)
        )
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius)
                .stroke(
                    report.warningCount > 0
                    ? SpendyTheme.healthWarn.opacity(0.25)
                    : SpendyTheme.healthOK.opacity(0.25),
                    lineWidth: 1
                )
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - Grid
    private func metricsGrid(_ report: HealthReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: SpendyTheme.paddingSm) {
            ForEach(Array(report.metrics.enumerated()), id: \.element.id) { i, metric in
                MetricCard(metric: metric)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.35).delay(Double(i) * 0.05 + 0.08), value: appeared)
            }
        }
    }

    // MARK: - CTA
    private func ctaButton(_ report: HealthReport) -> some View {
        GradientButton(
            "Go to Insights ✦",
            icon: "sparkles",
            gradient: SpendyTheme.accentGradient
        ) {
            // Switch to Insights tab (index 4) – no inline push
            appState.navigateTo(tab: 4)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"; return f.string(from: date)
    }
}

// MARK: - Metric Card
private struct MetricCard: View {
    let metric: HealthMetric
    @State private var barWidth: CGFloat = 0

    var statusColor: Color {
        switch metric.status {
        case .normal:     return SpendyTheme.healthOK
        case .borderline: return SpendyTheme.healthWarn
        case .warning:    return SpendyTheme.healthBad
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: metric.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor)
                Spacer()
                StatusBadge(label: metric.status.label, color: statusColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if !metric.unit.isEmpty {
                    Text(metric.unit).font(.caption2).foregroundStyle(SpendyTheme.textMuted)
                }
            }

            Text(metric.name).font(.caption).foregroundStyle(SpendyTheme.textMuted)

            // Progress bar – 2pt, subtle
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(height: 2)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(statusColor.opacity(0.8))
                        .frame(width: barWidth == 0 ? 0 : geo.size.width * metric.progress, height: 2)
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                        barWidth = geo.size.width
                    }
                }
            }
            .frame(height: 2)

            Text("Normal: \(metric.normalRange)")
                .font(.caption2).foregroundStyle(SpendyTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpendyTheme.paddingSm)
        .cardStyle()
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack { HealthResultsView().environment(s) }
}
