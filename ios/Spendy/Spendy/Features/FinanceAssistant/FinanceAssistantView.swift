import SwiftUI

struct FinanceAssistantView: View {
    @Environment(AppState.self) var appState
    @State private var summary: FinanceSummary? = nil
    @State private var isLoading = false
    @State private var displayedText = ""
    @State private var appeared = false
    private let service: APIServiceProtocol = MockAPIService()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpendyTheme.spacing) {
                if appState.hasSpendingData {
                    summaryHeader
                    if let summary {
                        riskChips(summary)
                        aiMessageCard(summary)
                    } else if isLoading {
                        loadingCard
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
                .disabled(isLoading)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            if summary == nil && appState.hasSpendingData {
                Task { await loadSummary() }
            }
        }
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
                Text("Total Spending")
                    .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("NT$\(Int(appState.totalMonthlySpent))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("this month")
                        .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                }
            }

            if let top = appState.topCategory {
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

    // MARK: - Risk Chips
    private func riskChips(_ s: FinanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("High-Risk Categories")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(s.riskCategories, id: \.self) { cat in
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(SpendyTheme.healthWarn)
                            Text(cat.rawValue).font(.subheadline).foregroundStyle(.white)
                            Text("NT$\(Int(s.categoryBreakdown[cat] ?? 0))")
                                .font(.caption).foregroundStyle(SpendyTheme.healthWarn)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(SpendyTheme.healthWarn.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SpendyTheme.healthWarn.opacity(0.25), lineWidth: 1))
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
                Text("Analysis complete").font(.caption2).foregroundStyle(SpendyTheme.healthOK)
            }

            Text(displayedText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
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
            Text("Add expenses in the Spending tab, or load the demo from Profile.")
                .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Actions
    private func loadSummary() async {
        isLoading = true
        displayedText = ""
        let result = await service.fetchFinanceSummary(entries: appState.spendingEntries)
        summary = result
        isLoading = false
        startTypewriter(text: result.aiMessage)
    }

    private func startTypewriter(text: String) {
        displayedText = ""
        var delay = 0.0
        for char in text {
            let c = char
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                displayedText.append(c)
            }
            delay += 0.012
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack { FinanceAssistantView().environment(s) }
}
