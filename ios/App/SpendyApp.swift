import SwiftUI

@main
struct SpendyApp: App {
    @State private var appState = AppState()
    @State private var appEnvironment = AppEnvironment(route: .mock) // 可更動：.mock / .remote / .onDevice

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
        }
    }
}
