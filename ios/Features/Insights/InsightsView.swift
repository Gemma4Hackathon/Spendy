import SwiftUI

struct InsightsView: View {
    @Environment(AppState.self) var appState
    @Environment(AppEnvironment.self) var appEnvironment
    @State private var appeared = false
    @State private var gaugeScore: CGFloat = 0
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            SpendyTheme.background.ignoresSafeArea()
            if let result = appState.insightResult {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SpendyTheme.spacing) {
                        analysisMonthPicker
                        headerSection
                        riskGauge(result)
                        signalPathSection(result)
                        actionPlanSection(result)
                        findingsSection(result)
                        footerNote
                    }
                    .padding(.horizontal, SpendyTheme.padding)
                    .padding(.top, 8)
                    .padding(.bottom, 50)
                }
            } else {
                emptyState
            }

            if isGenerating && appState.insightResult != nil {
                generatingOverlay
                    .padding(.horizontal, SpendyTheme.padding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let err = errorMessage, appState.insightResult != nil {
                errorBanner(err)
                    .padding(.horizontal, SpendyTheme.padding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isGenerating {
                    ProgressView().tint(SpendyTheme.accent)
                } else if appState.insightResult != nil && appState.canGenerateInsights {
                    Button {
                        Task { await generateInsights() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(SpendyTheme.accent)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            if let score = appState.insightResult?.overallRiskScore {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 1.2)) { gaugeScore = CGFloat(score) }
                }
            }
        }
        .onChange(of: appState.analysisMonth) { _, _ in
            errorMessage = nil
            gaugeScore = 0
            if let score = appState.insightResult?.overallRiskScore {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.8)) {
                        gaugeScore = CGFloat(score)
                    }
                }
            }
        }
    }

    // MARK: - Analysis Month
    private var analysisMonthPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.stepAnalysisMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SpendyTheme.accent)
                    .frame(width: 40, height: 36)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("AI analysis month")
                    .font(.caption2)
                    .foregroundStyle(SpendyTheme.textMuted)
                Text(appState.analysisMonthLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.stepAnalysisMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appState.canGoAnalysisForward ? SpendyTheme.accent : SpendyTheme.textMuted)
                    .frame(width: 40, height: 36)
            }
            .disabled(!appState.canGoAnalysisForward)
        }
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.35), value: appeared)
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(SpendyTheme.accent)
                Text("Spendy Intelligence")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(SpendyTheme.accent)
                    .textCase(.uppercase).kerning(0.8)
            }
            Text("Health × Finance Analysis")
                .font(.title2).fontWeight(.bold).foregroundStyle(.white)
            Text("AI-detected patterns for \(appState.analysisMonthLabel) spending and your health markers.")
                .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - Risk Gauge
    private func riskGauge(_ result: InsightResult) -> some View {
        HStack(spacing: 24) {
            // Gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: gaugeScore / 100)
                    .stroke(
                        AngularGradient(
                            colors: [SpendyTheme.healthOK, SpendyTheme.healthWarn, SpendyTheme.healthBad],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(result.overallRiskScore)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(gaugeColor(result.overallRiskScore))
                    Text("Risk").font(.caption).foregroundStyle(SpendyTheme.textMuted)
                }
            }
            .frame(width: 130, height: 130)

            // Metadata
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("At-Risk Spending").font(.caption).foregroundStyle(SpendyTheme.textMuted)
                    Text("NT$\(Int(result.monthlySpendingAtRisk))/mo")
                        .font(.title3).fontWeight(.bold).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patterns Found").font(.caption).foregroundStyle(SpendyTheme.textMuted)
                    Text("\(result.keyFindings.count) cross-domain")
                        .font(.title3).fontWeight(.bold).foregroundStyle(.white)
                }
                StatusBadge(
                    label: result.overallRiskScore >= 70 ? "High Risk" : "Moderate",
                    color: result.overallRiskScore >= 70 ? SpendyTheme.healthBad : SpendyTheme.healthWarn
                )
            }
            Spacer()
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.07), value: appeared)
    }

    // MARK: - Findings
    private func findingsSection(_ result: InsightResult) -> some View {
        VStack(spacing: SpendyTheme.spacing) {
            SectionHeader("Key Findings", subtitle: "Habit → Health → Action")
            ForEach(Array(result.keyFindings.enumerated()), id: \.element.id) { i, finding in
                InsightConnectionCard(connection: finding)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.4).delay(Double(i) * 0.1 + 0.14), value: appeared)
            }
        }
    }

    private func signalPathSection(_ result: InsightResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Signal Path", subtitle: "How spending connects to health markers")

            ForEach(Array(result.keyFindings.prefix(3).enumerated()), id: \.element.id) { index, finding in
                HStack(spacing: 10) {
                    PathNode(
                        label: finding.cause,
                        icon: finding.icon,
                        color: accentColor(for: finding)
                    )
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SpendyTheme.textMuted)
                    PathNode(
                        label: finding.healthImpact,
                        icon: "heart.text.clipboard.fill",
                        color: accentColor(for: finding)
                    )
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.06 + 0.12), value: appeared)
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.10), value: appeared)
    }

    private func actionPlanSection(_ result: InsightResult) -> some View {
        let plan = result.actionPlan ?? InsightResult.demo.actionPlan
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("7-Day Action Plan", subtitle: "Concrete movement and food changes")
            if let plan {
                VStack(alignment: .leading, spacing: 12) {
                    actionPlanCard(
                        title: "Movement",
                        icon: "figure.run",
                        color: SpendyTheme.healthOK,
                        item: plan.movement
                    )
                    actionPlanCard(
                        title: "Food",
                        icon: "fork.knife",
                        color: SpendyTheme.healthWarn,
                        item: plan.food
                    )
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.12), value: appeared)
    }

    private func actionPlanCard(
        title: String,
        icon: String,
        color: Color,
        item: InsightPlanItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.recommendation)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.whyItMatters)
                .font(.caption2)
                .foregroundStyle(SpendyTheme.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.targetMetric)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(item.timeframe)
                    .font(.caption2)
                    .foregroundStyle(SpendyTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Footer
    private var footerNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.caption)
            Text("Generated by Gemma 4. For behavioral guidance only — not medical advice.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SpendyTheme.textMuted)
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
    }

    // MARK: - Empty / Generate
    private var emptyState: some View {
        VStack(spacing: 20) {
            analysisMonthPicker
            Image(systemName: "sparkles").font(.system(size: 52)).foregroundStyle(SpendyTheme.textMuted)
            Text("No insights yet").font(.title3).fontWeight(.semibold).foregroundStyle(.white)
            if let err = errorMessage {
                Text(err)
                    .font(.caption).foregroundStyle(SpendyTheme.healthBad)
                    .multilineTextAlignment(.center)
            } else {
                Text("Complete a health scan and use a month with spending, then tap Generate Insights.")
                    .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
            if appState.canGenerateInsights {
                GradientButton("Generate Insights", icon: "sparkles", isLoading: isGenerating) {
                    Task { await generateInsights() }
                }
                .padding(.horizontal, 40)
            }
        }
        .padding(40)
    }

    // MARK: - AI Action
    private func generateInsights() async {
        isGenerating = true
        appState.isGeneratingInsights = true
        errorMessage = nil
        defer {
            isGenerating = false
            appState.isGeneratingInsights = false
        }

        guard let healthReport = appState.healthReport else {
            errorMessage = "Complete a health scan before generating insights."
            return
        }
        guard appState.hasAnalysisSpendingData else {
            errorMessage = "No expenses found for \(appState.analysisMonthLabel). Switch months or add expenses first."
            return
        }

        do {
            let result = try await appEnvironment.router.insightGenerator.generateInsights(
                profile: appState.profile,
                spending: appState.analysisEntries,
                health: healthReport
            )
            appState.setInsightResult(result, for: appState.analysisMonth)
            appState.lastInferenceSource = appEnvironment.router.currentSourceLabel.rawValue
            appState.saveToDisk()
            withAnimation(.easeOut(duration: 1.2)) {
                gaugeScore = CGFloat(result.overallRiskScore)
            }
        } catch {
            errorMessage = error.localizedDescription
            appEnvironment.markServiceError(error)
        }
    }

    private var generatingOverlay: some View {
        HStack(spacing: 10) {
            ProgressView().tint(SpendyTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generating insights")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text("Running Gemma 4 locally on this iPhone.")
                    .font(.caption)
                    .foregroundStyle(SpendyTheme.textMuted)
            }
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SpendyTheme.healthWarn)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(SpendyTheme.healthWarn.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius)
                .stroke(SpendyTheme.healthWarn.opacity(0.35), lineWidth: 1)
        )
    }

    private func gaugeColor(_ score: Int) -> Color {
        score < 40 ? SpendyTheme.healthOK : score < 70 ? SpendyTheme.healthWarn : SpendyTheme.healthBad
    }

    private func accentColor(for connection: InsightConnection) -> Color {
        switch connection.accentColor {
        case "red": return SpendyTheme.healthBad
        case "amber": return SpendyTheme.healthWarn
        default: return SpendyTheme.finance
        }
    }
}

private struct PathNode: View {
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm)
                .stroke(color.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Insight Connection Card (redesigned: left accent strip)
private struct InsightConnectionCard: View {
    let connection: InsightConnection

    var accentColor: Color {
        switch connection.accentColor {
        case "red":   return SpendyTheme.healthBad
        case "amber": return SpendyTheme.healthWarn
        default:      return SpendyTheme.finance
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                Image(systemName: connection.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.cause)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(accentColor)
                        Text(connection.healthImpact)
                            .font(.caption).foregroundStyle(accentColor)
                    }
                }
                Spacer()
                StatusBadge(label: "Warning", color: accentColor)
            }
            .padding(SpendyTheme.padding)

            // Thin divider
            Rectangle()
                .fill(SpendyTheme.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                // Spending pattern
                infoBlock(label: "Spending Pattern", text: connection.causeDetail, color: .white.opacity(0.85))

                // Impact arrow
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(accentColor).font(.body)
                        Text("Impact").font(.caption2).foregroundStyle(SpendyTheme.textMuted)
                    }
                    Spacer()
                }

                // Health impact
                infoBlock(label: "Health Impact", text: connection.healthDetail, color: accentColor)

                // Risk callout
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(accentColor).padding(.top, 1)
                    Text(connection.risk)
                        .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))

                // Actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommended Actions")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(SpendyTheme.textMuted)
                        .textCase(.uppercase).kerning(0.5)

                    ForEach(connection.actions) { action in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15)).foregroundStyle(SpendyTheme.healthOK)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                                Text(action.description)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.76))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(action.expectedOutcome)
                                    .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                                HStack(spacing: 4) {
                                    Image(systemName: "clock").font(.caption2)
                                    Text(action.timeframe)
                                }.font(.caption2).foregroundStyle(SpendyTheme.accent)
                            }
                        }
                    }
                }
            }
            .padding(SpendyTheme.padding)
        }
        .cardStyle()
        .overlay(alignment: .leading) {
            // Accent left strip
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: SpendyTheme.cornerRadius,
                        bottomLeadingRadius: SpendyTheme.cornerRadius
                    )
                )
        }
    }

    private func infoBlock(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(SpendyTheme.textMuted)
                .textCase(.uppercase).kerning(0.5)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(color)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack {
        InsightsView()
            .environment(s)
            .environment(AppEnvironment.previewMock())
    }
}
