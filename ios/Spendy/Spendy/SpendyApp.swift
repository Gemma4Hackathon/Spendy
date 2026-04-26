import SwiftUI

@main
struct SpendyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
