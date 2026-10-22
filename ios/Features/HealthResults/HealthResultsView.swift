import SwiftUI

struct HealthResultsView: View {
    @Environment(AppState.self) var appState
    @State private var appeared = false
    @State private var showEvidenceTrace = false

    var body: some View {
        ZStack {
            SpendyTheme.background.ignoresSafeArea()
            if let report = appState.healthReport {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SpendyTheme.spacing) {
                        summaryBanner(report)
                        metricsGrid(report)
                        evidenceTraceSection(report)
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
                Text(report.abnormalCount == 0
                     ? "All \(report.metrics.count) results are within range"
                     : "\(report.abnormalCount) of \(report.metrics.count) results need attention")
                    .font(.headline).fontWeight(.semibold).foregroundStyle(.white)
                Text("Scanned \(formattedDate(report.reportDate))  ·  \(report.labName)")
                    .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                if report.labName.contains("OCR") {
                    Text("Every value is checked against the report text; flags come from the report.")
                        .font(.caption2).foregroundStyle(SpendyTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            ForEach(Array(attentionFirst(report.metrics).enumerated()), id: \.element.id) { i, metric in
                MetricCard(metric: metric)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.35).delay(Double(i) * 0.05 + 0.08), value: appeared)
            }
        }
    }

    private func evidenceTraceSection(_ report: HealthReport) -> some View {
        let trace = report.evidenceTrace ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Evidence Trace", subtitle: "How the report was interpreted")
                Spacer()
                if !trace.isEmpty {
                    Button(showEvidenceTrace ? "Hide" : "Show") {
                        withAnimation(.easeOut(duration: SpendyTheme.motionFast)) {
                            showEvidenceTrace.toggle()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SpendyTheme.accent)
                }
            }
            if trace.isEmpty {
                Text("No evidence trace was produced for this scan.")
                    .font(.subheadline)
                    .foregroundStyle(SpendyTheme.textMuted)
            } else {
                let visibleTrace = showEvidenceTrace ? trace : Array(trace.prefix(1))
                ForEach(Array(visibleTrace.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(SpendyTheme.accent.opacity(0.85))
                            .clipShape(Circle())
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !showEvidenceTrace && trace.count > 1 {
                    Text("\(trace.count - 1) more evidence notes hidden.")
                        .font(.caption)
                        .foregroundStyle(SpendyTheme.textMuted)
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.35).delay(0.16), value: appeared)
    }

    // MARK: - CTA
    private func ctaButton(_ report: HealthReport) -> some View {
        GradientButton(
            "Go to Insights",
            icon: "sparkles",
            gradient: SpendyTheme.accentGradient
        ) {
            // Switch to Insights tab (index 4) – no inline push
            appState.navigateTo(tab: 4)
        }
    }

    /// High, then Borderline, then Normal; report order within each group.
    private func attentionFirst(_ metrics: [HealthMetric]) -> [HealthMetric] {
        func rank(_ status: HealthStatus) -> Int {
            switch status {
            case .warning: return 0
            case .borderline: return 1
            case .normal: return 2
            }
        }
        return metrics.enumerated()
            .sorted { (rank($0.element.status), $0.offset) < (rank($1.element.status), $1.offset) }
            .map(\.element)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"; return f.string(from: date)
    }
}

// MARK: - Metric Card
private struct MetricCard: View {
    let metric: HealthMetric

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

            // No bar here: a fixed-length bar per status looked like the value's position.
            if !metric.normalRange.isEmpty {
                Text("Reference \(metric.normalRange)")
                    .font(.caption2).foregroundStyle(SpendyTheme.textMuted)
            }
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
