import SwiftUI

@main
struct SpendyApp: App {
    @State private var appState = AppState()
    @State private var appEnvironment = AppEnvironment(route: .remote) // .mock / .remote / .onDevice

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
        }
    }
}
