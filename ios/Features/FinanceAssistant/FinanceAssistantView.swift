import SwiftUI

struct FinanceAssistantView: View {
    @Environment(AppState.self) var appState
    @Environment(AppEnvironment.self) var appEnvironment
    @State private var summary: FinanceSummary? = nil
    @State private var isLoading = false
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpendyTheme.spacing) {
                analysisMonthPicker
                if appState.hasAnalysisSpendingData {
                    summaryHeader
                    if let summary {
                        riskChips(summary)
                        spendingChart(summary)
                        aiMessageCard(summary)
                    } else if isLoading {
                        loadingCard
                    } else {
                        readyCard
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, SpendyTheme.padding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .spendyBackground()
        .navigationTitle("Fin Assistant")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadSummary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(SpendyTheme.accent)
                }
                .disabled(isLoading || !appState.hasAnalysisSpendingData)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            summary = appState.financeSummary(for: appState.analysisMonth)
        }
        .onChange(of: appState.analysisMonth) { _, _ in
            summary = appState.financeSummary(for: appState.analysisMonth)
        }
    }

    // MARK: - Analysis Month
    private var analysisMonthPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.stepAnalysisMonth(by: -1)
                    summary = appState.financeSummary(for: appState.analysisMonth)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SpendyTheme.accent)
                    .frame(width: 40, height: 36)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Analyzing")
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
                    summary = appState.financeSummary(for: appState.analysisMonth)
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

    // MARK: - Summary Header
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.fill").font(.title3).foregroundStyle(SpendyTheme.finance)
                Text("AI Finance Analysis").font(.headline).fontWeight(.semibold).foregroundStyle(.white)
                Spacer()
                if isLoading {
                    ProgressView().tint(SpendyTheme.accent).scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(SpendyTheme.healthOK)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing \(appState.analysisMonthLabel) spending")
                    .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("NT$\(Int(summary?.totalSpent ?? appState.analysisTotalSpent))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("tracked")
                        .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                }
            }

            if let top = summary?.topCategory ?? appState.analysisTopCategory {
                HStack(spacing: 6) {
                    Image(systemName: top.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(SpendyTheme.textMuted)
                    Text("Top: \(top.rawValue)")
                        .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(SpendyTheme.accent)
                Text("Ready to analyze")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            Text("Tap refresh to run Gemma 4 on \(appState.analysisMonthLabel) spending only.")
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Risk Chips
    private func riskChips(_ s: FinanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Budget Levers", subtitle: "Categories with the most room to adjust")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(s.riskCategories, id: \.self) { cat in
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SpendyTheme.finance)
                            Text(cat.rawValue).font(.subheadline).foregroundStyle(.white)
                            Text("NT$\(Int(s.categoryBreakdown[cat] ?? 0))")
                                .font(.caption).foregroundStyle(SpendyTheme.finance)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(SpendyTheme.finance.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SpendyTheme.finance.opacity(0.25), lineWidth: 1))
                    }
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.07), value: appeared)
    }

    // MARK: - AI Message
    private func aiMessageCard(_ s: FinanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    SpendyTheme.accent
                    Image(systemName: "sparkles").foregroundStyle(.white).font(.caption)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                Text("Spendy AI").font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                Spacer()
                if isLoading {
                    HStack(spacing: 5) {
                        ProgressView().tint(SpendyTheme.accent).scaleEffect(0.6)
                        Text("Generating")
                    }
                    .font(.caption2)
                    .foregroundStyle(SpendyTheme.accent)
                } else {
                    Text("Analysis complete").font(.caption2).foregroundStyle(SpendyTheme.healthOK)
                }
            }

            if !s.insightItems.isEmpty {
                structuredAdvice(s)
            } else {
                MarkdownContentView(
                    text: s.aiMessage,
                    bodyFont: .subheadline,
                    textColor: .white.opacity(0.88),
                    accentColor: .white
                )
                .transition(.opacity)
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .animation(.easeIn(duration: 0.4), value: summary?.aiMessage)
    }

    private func spendingChart(_ s: FinanceSummary) -> some View {
        let rows = s.categoryBreakdown.sorted { $0.value > $1.value }.prefix(5)
        let maxAmount = rows.map(\.value).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Spending Map", subtitle: "Where this month is concentrated")

            ForEach(Array(rows), id: \.key) { category, amount in
                let share = s.totalSpent > 0 ? Int((amount / s.totalSpent) * 100) : 0
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(category.rawValue, systemImage: category.icon)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Text("NT$\(Int(amount)) · \(share)%")
                            .font(.caption)
                            .foregroundStyle(SpendyTheme.textMuted)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule()
                                .fill(Color(hex: category.colorHex))
                                .frame(width: max(10, proxy.size.width * CGFloat(amount / maxAmount)))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.10), value: appeared)
    }

    private func structuredAdvice(_ s: FinanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(s.shortTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(s.quickTake)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(s.insightItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            SpendyTheme.finance.opacity(0.14)
                            Image(systemName: item.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SpendyTheme.finance)
                        }
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(item.amount)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(SpendyTheme.finance)
                            }
                            Text(item.impact)
                                .font(.caption)
                                .foregroundStyle(SpendyTheme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .insetSurface()
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SpendyTheme.healthOK)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next 7 days")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(SpendyTheme.healthOK)
                    Text(s.primaryAction)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(SpendyTheme.healthOK.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))

            if !s.aiMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "text.bubble.fill")
                            .font(.caption)
                            .foregroundStyle(SpendyTheme.accent)
                        Text("Spendy AI notes")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(SpendyTheme.textMuted)
                            .textCase(.uppercase)
                            .kerning(0.5)
                    }

                    MarkdownContentView(
                        text: s.aiMessage,
                        bodyFont: .subheadline,
                        textColor: .white.opacity(0.88),
                        accentColor: .white
                    )
                }
                .padding(12)
                .insetSurface()
            }
        }
    }

    // MARK: - Loading
    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(SpendyTheme.accent).scaleEffect(1.2)
            Text("Analyzing your spending...")
                .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .cardStyle()
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 52))
                .foregroundStyle(SpendyTheme.textMuted)
            Text("No spending data")
                .font(.title3).fontWeight(.semibold).foregroundStyle(.white)
            Text("No expenses found for \(appState.analysisMonthLabel). Switch months here, add expenses in Spending, or load the finance demo from Profile.")
                .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Actions
    private func loadSummary() async {
        guard !isLoading else { return }
        guard appState.hasAnalysisSpendingData else { return }
        isLoading = true
        defer { isLoading = false }
        let entries = appState.analysisEntries
        let result = await appEnvironment.router.financeProvider.fetchFinanceSummary(entries: entries)
        summary = result
        appState.setFinanceSummary(result, for: appState.analysisMonth)
        appState.lastInferenceSource = appEnvironment.router.currentSourceLabel.rawValue
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack {
        FinanceAssistantView()
            .environment(s)
            .environment(AppEnvironment.previewMock())
    }
}
