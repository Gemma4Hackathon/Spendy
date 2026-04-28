import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {

            // Tab 0 – Profile
            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
            .tag(0)

            // Tab 1 – Spending
            NavigationStack {
                SpendingView()
            }
            .tabItem { Label("Spending", systemImage: "creditcard.fill") }
            .tag(1)

            // Tab 2 – Finance Assistant
            NavigationStack {
                FinanceAssistantView()
            }
            .tabItem { Label("Fin Assistant", systemImage: "chart.bar.xaxis.ascending.badge.clock") }
            .tag(2)

            // Tab 3 – Health Scan → Results (navigation within tab)
            NavigationStack {
                HealthScanView()
            }
            .tabItem { Label("Health Scan", systemImage: "heart.text.clipboard.fill") }
            .tag(3)

            // Tab 4 – Insights
            NavigationStack {
                InsightsView()
            }
            .tabItem { Label("Insights", systemImage: "sparkles") }
            .tag(4)
        }
        .tint(SpendyTheme.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    let state = AppState()
    state.loadDemo()
    return MainTabView().environment(state)
}
