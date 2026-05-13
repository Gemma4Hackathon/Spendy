import SwiftUI

@main
struct SpendyApp: App {
    @State private var appState = AppState()
    @State private var appEnvironment = AppEnvironment(route: .onDevice) // .mock / .remote / .onDevice

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
                // Trigger model load on startup (route setter is bypassed during init)
                .task {
                    if appEnvironment.route == .onDevice {
                        await appEnvironment.loadOnDeviceModelIfNeeded()
                    }
                }
        }
    }
}
