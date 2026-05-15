import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var appeared = false
    @State private var showProfile = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpendyTheme.spacing) {
                heroSection
                primaryActionSection
                signalGrid
                recentInsightSection
            }
            .padding(.horizontal, SpendyTheme.padding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .spendyBackground()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(SpendyTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                ProfileView()
                    .environment(appState)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StatusBadge(label: modelStatusLabel, color: modelStatusColor)
                Spacer()
                Text(appState.lastInferenceSource)
                    .font(.caption)
                    .foregroundStyle(SpendyTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Health-aware spending")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("See which habits are affecting both your budget and your health markers.")
                    .font(.subheadline)
                    .foregroundStyle(SpendyTheme.textMuted)
                    .lineSpacing(4)
            }

            HStack(spacing: 12) {
                HeroMetric(
                    title: "At-risk",
                    value: atRiskAmount,
                    subtitle: appState.insightResult == nil ? "Generate insights" : "per month",
                    color: SpendyTheme.healthWarn
                )
                HeroMetric(
                    title: "Risk score",
                    value: riskScoreLabel,
                    subtitle: riskSubtitle,
                    color: riskColor
                )
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    private var primaryActionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Next Best Action", subtitle: "One step to move the demo forward")

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    actionColor.opacity(0.14)
                    Image(systemName: actionIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(actionColor)
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))

                VStack(alignment: .leading, spacing: 5) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(actionDescription)
                        .font(.caption)
                        .foregroundStyle(SpendyTheme.textMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: performPrimaryAction) {
                HStack {
                    Text(actionButtonTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(actionColor)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.06), value: appeared)
    }

    private var signalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: SpendyTheme.paddingSm) {
            TodaySignalCard(
                title: "Spending",
                value: "NT$\(Int(appState.totalMonthlySpent))",
                subtitle: "\(appState.filteredEntries.count) entries this month",
                icon: "creditcard.fill",
                color: SpendyTheme.finance
            )
            TodaySignalCard(
                title: "Health",
                value: healthSignalValue,
                subtitle: healthSignalSubtitle,
                icon: "heart.text.clipboard.fill",
                color: healthSignalColor
            )
            TodaySignalCard(
                title: "Top category",
                value: appState.topCategory?.rawValue ?? "No data",
                subtitle: topCategorySubtitle,
                icon: appState.topCategory?.icon ?? "chart.bar.fill",
                color: topCategoryColor
            )
            TodaySignalCard(
                title: "Insight",
                value: appState.insightResult == nil ? "Pending" : "Ready",
                subtitle: appState.insightResult == nil ? "Run local analysis" : "\(appState.insightResult?.keyFindings.count ?? 0) findings",
                icon: "sparkles",
                color: SpendyTheme.accent
            )
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.12), value: appeared)
    }

    private var recentInsightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Current Signals", subtitle: "What Spendy can analyze now")

            SignalRow(
                icon: appState.hasSpendingData ? "checkmark.circle.fill" : "circle",
                title: "Spending data",
                detail: appState.hasSpendingData ? "Monthly spending is available." : "Add spending or load finance demo data.",
                color: appState.hasSpendingData ? SpendyTheme.healthOK : SpendyTheme.textMuted
            )
            SignalRow(
                icon: appState.hasHealthData ? "checkmark.circle.fill" : "circle",
                title: "Health report",
                detail: appState.hasHealthData ? "Health markers are available." : "Scan a real report image.",
                color: appState.hasHealthData ? SpendyTheme.healthOK : SpendyTheme.textMuted
            )
            SignalRow(
                icon: appEnvironment.canRunOnDeviceInference ? "checkmark.circle.fill" : "clock.fill",
                title: "Local model",
                detail: modelStatusDescription,
                color: modelStatusColor
            )
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.18), value: appeared)
    }
}

// MARK: - Derived State
private extension TodayView {
    var atRiskAmount: String {
        guard let insight = appState.insightResult else {
            if appState.hasSpendingData && !appState.hasHealthData { return "Scan health" }
            if appState.canGenerateInsights { return "Generate" }
            return "--"
        }
        return "NT$\(Int(insight.monthlySpendingAtRisk))"
    }

    var riskScoreLabel: String {
        guard let score = appState.insightResult?.overallRiskScore else {
            if appState.hasSpendingData && !appState.hasHealthData { return "Pending" }
            if appState.canGenerateInsights { return "Ready" }
            return "--"
        }
        return "\(score)"
    }

    var riskSubtitle: String {
        guard let score = appState.insightResult?.overallRiskScore else {
            if appState.hasSpendingData && !appState.hasHealthData { return "health scan needed" }
            if appState.canGenerateInsights { return "tap Insights" }
            return "No score yet"
        }
        return score >= 70 ? "high risk" : score >= 40 ? "moderate" : "low risk"
    }

    var riskColor: Color {
        guard let score = appState.insightResult?.overallRiskScore else { return SpendyTheme.textMuted }
        return score >= 70 ? SpendyTheme.healthBad : score >= 40 ? SpendyTheme.healthWarn : SpendyTheme.healthOK
    }

    var healthSignalValue: String {
        guard let report = appState.healthReport else { return "No scan" }
        return "\(report.abnormalCount) flagged"
    }

    var healthSignalSubtitle: String {
        guard let report = appState.healthReport else { return "Scan a report" }
        return report.warningCount > 0 ? "\(report.warningCount) high markers" : "No high markers"
    }

    var healthSignalColor: Color {
        guard let report = appState.healthReport else { return SpendyTheme.textMuted }
        return report.warningCount > 0 ? SpendyTheme.healthBad : report.abnormalCount > 0 ? SpendyTheme.healthWarn : SpendyTheme.healthOK
    }

    var topCategorySubtitle: String {
        guard let category = appState.topCategory,
              let amount = appState.spendingByCategory[category] else {
            return "No category yet"
        }
        return "NT$\(Int(amount)) this month"
    }

    var topCategoryColor: Color {
        guard let category = appState.topCategory else { return SpendyTheme.textMuted }
        return Color(hex: category.colorHex)
    }

    var modelStatusLabel: String {
        switch appEnvironment.onDeviceInstallState {
        case .ready: return "On-device ready"
        case .downloading: return "Loading model"
        case .failed: return "Model issue"
        case .notInstalled: return "Model pending"
        }
    }

    var modelStatusDescription: String {
        switch appEnvironment.onDeviceInstallState {
        case .ready: return "Gemma 4 is ready for local inference."
        case .downloading: return "Gemma 4 is loading on this iPhone."
        case .failed: return "Model load failed. Check Xcode logs."
        case .notInstalled: return "Model has not finished initializing."
        }
    }

    var modelStatusColor: Color {
        switch appEnvironment.onDeviceInstallState {
        case .ready: return SpendyTheme.healthOK
        case .downloading: return SpendyTheme.healthWarn
        case .failed: return SpendyTheme.healthBad
        case .notInstalled: return SpendyTheme.textMuted
        }
    }

    var actionTitle: String {
        if !appState.hasSpendingData { return "Load finance demo" }
        if !appState.hasHealthData { return "Scan a health report" }
        if appState.insightResult == nil { return "Generate cross-domain insights" }
        return "Review your insight"
    }

    var actionDescription: String {
        if !appState.hasSpendingData {
            return "Use sample spending so the demo can focus on real health scanning and local insight generation."
        }
        if !appState.hasHealthData {
            return "Upload or photograph a checkup report so Spendy can extract health markers locally."
        }
        if appState.insightResult == nil {
            return "Both spending and health data are ready. Run the local model to produce findings."
        }
        return "Your latest local analysis is ready. Review the risk path and recommended actions."
    }

    var actionButtonTitle: String {
        if !appState.hasSpendingData { return "Load Finance Demo" }
        if !appState.hasHealthData { return "Open Health Scan" }
        return "Open Insights"
    }

    var actionIcon: String {
        if !appState.hasSpendingData { return "creditcard.fill" }
        if !appState.hasHealthData { return "heart.text.clipboard.fill" }
        return "sparkles"
    }

    var actionColor: Color {
        if !appState.hasSpendingData { return SpendyTheme.finance }
        if !appState.hasHealthData { return SpendyTheme.healthOK }
        return SpendyTheme.accent
    }

    func performPrimaryAction() {
        if !appState.hasSpendingData {
            appState.loadFinanceDemo()
        } else if !appState.hasHealthData {
            appState.navigateTo(tab: 3)
        } else {
            appState.navigateTo(tab: 4)
        }
    }
}

private struct HeroMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(SpendyTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SpendyTheme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
    }
}

private struct TodaySignalCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(SpendyTheme.textMuted)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(SpendyTheme.textMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(SpendyTheme.paddingSm)
        .cardStyle()
    }
}

private struct SignalRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SpendyTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    let state = AppState()
    state.loadDemo()
    return NavigationStack {
        TodayView()
            .environment(state)
            .environment(AppEnvironment.previewMock())
    }
}
