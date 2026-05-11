import SwiftUI

struct SpendingView: View {
    @Environment(AppState.self) var appState
    @State private var showAddSheet = false
    @State private var appeared = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd"; return f
    }()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SpendyTheme.spacing) {
                    monthPicker          // Optimization 2
                    heroTotal
                    chartSection         // Optimization 3
                    categoryBreakdown
                    recentEntries
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .spendyBackground()

            // FAB
            Button { showAddSheet = true } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(SpendyTheme.accent)
                    .clipShape(Circle())
            }
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle("Spending")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAddSheet) { AddSpendingView() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }

    // MARK: - Month Picker (Optimization 2)
    private var monthPicker: some View {
        @Bindable var state = appState
        return HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.stepMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SpendyTheme.accent)
                    .frame(width: 40, height: 36)
            }

            Spacer()

            Text(appState.selectedMonthLabel)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.stepMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appState.canGoForward ? SpendyTheme.accent : SpendyTheme.textMuted)
                    .frame(width: 40, height: 36)
            }
            .disabled(!appState.canGoForward)
        }
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.35), value: appeared)
    }

    // MARK: - Hero Total
    private var heroTotal: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total Spending")
                .font(.subheadline)
                .foregroundStyle(SpendyTheme.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("NT$")
                    .font(.title2).fontWeight(.semibold)
                    .foregroundStyle(SpendyTheme.textMuted)
                Text(String(format: "%.0f", appState.totalMonthlySpent))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Text("\(appState.filteredEntries.count) entries · \(appState.selectedMonthLabel)")
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
        }
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - Chart Section (Optimization 3)
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Daily Breakdown")
            SpendingChartView(entries: appState.filteredEntries)
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)
    }

    // MARK: - Category Breakdown
    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("By Category")
            let sorted = appState.spendingByCategory
                .sorted { $0.value > $1.value }
                .prefix(5)
            let maxVal = sorted.first?.value ?? 1

            if sorted.isEmpty {
                Text("No data for this month.")
                    .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
            } else {
                ForEach(sorted, id: \.key) { cat, amount in
                    HStack(spacing: 12) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: cat.colorHex))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(cat.rawValue).font(.subheadline).foregroundStyle(.white)
                                Spacer()
                                Text("NT$\(Int(amount))")
                                    .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.07)).frame(height: 2)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: cat.colorHex).opacity(0.75))
                                        .frame(width: geo.size.width * (amount / maxVal), height: 2)
                                }
                            }
                            .frame(height: 2)
                        }
                    }
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.10), value: appeared)
    }

    // MARK: - Entries List
    private var recentEntries: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Recent", subtitle: "Swipe to delete")

            if appState.filteredEntries.isEmpty {
                Text("No expenses for this month. Tap + to add one.")
                    .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(appState.filteredEntries) { entry in
                    entryRow(entry)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    appState.spendingEntries.removeAll { $0.id == entry.id }
                                    PersistenceManager.shared.save(
                                        appState.spendingEntries,
                                        fileName: "spendy_spending"
                                    )
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
    }

    private func entryRow(_ entry: SpendingEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Color(hex: entry.category.colorHex).opacity(0.12)
                Image(systemName: entry.category.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: entry.category.colorHex))
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                Text(dateFormatter.string(from: entry.date))
                    .font(.caption).foregroundStyle(SpendyTheme.textMuted)
            }
            Spacer()
            Text("NT$\(Int(entry.amount))")
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack { SpendingView().environment(s) }
}
