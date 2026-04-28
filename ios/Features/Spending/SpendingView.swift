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
                    heroTotal
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

    // MARK: - Hero Total (no card — number speaks for itself)
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
            }
            Text("\(appState.spendingEntries.count) entries · this month")
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
        }
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - Category Breakdown
    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("By Category")
            let sorted = appState.spendingByCategory
                .sorted { $0.value > $1.value }
                .prefix(5)
            let maxVal = sorted.first?.value ?? 1

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
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.07), value: appeared)
    }

    // MARK: - Entries List
    private var recentEntries: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Recent", subtitle: "Swipe to delete")

            if appState.spendingEntries.isEmpty {
                Text("No expenses yet. Tap + to add one.")
                    .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(appState.spendingEntries) { entry in
                    entryRow(entry)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    appState.spendingEntries.removeAll { $0.id == entry.id }
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
        .animation(.easeOut(duration: 0.4).delay(0.12), value: appeared)
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
