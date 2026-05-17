import Observation
import Foundation

enum OnDeviceModelInstallState: String {
    case notInstalled
    case downloading
    case ready
    case failed
}

@Observable
final class AppEnvironment {
    let router: ServiceRouter
    var onDeviceInstallState: OnDeviceModelInstallState
    var lastServiceErrorMessage: String?

    init(
        route: InferenceRoute = .mock,
        onDeviceInstallState: OnDeviceModelInstallState = .notInstalled
    ) {
        self.router = ServiceRouter(route: route)
        self.onDeviceInstallState = onDeviceInstallState
    }

    var route: InferenceRoute {
        get { router.route }
        set {
            router.route = newValue
            if newValue == .onDevice {
                Task { await loadOnDeviceModelIfNeeded() }
            }
        }
    }

    var canRunOnDeviceInference: Bool {
        route == .onDevice && onDeviceInstallState == .ready && CactusManager.shared.isReady
    }

    func markServiceError(_ error: Error) {
        lastServiceErrorMessage = error.localizedDescription
    }

    // MARK: - On-Device Model Loading

    /// Triggers CactusManager to load the Gemma 4 model and keeps
    /// `onDeviceInstallState` in sync so the UI can react.
    @MainActor
    func loadOnDeviceModelIfNeeded() async {
        guard case .idle = CactusManager.shared.state else {
            // Already loading or loaded — just sync the badge
            syncInstallState()
            return
        }
        onDeviceInstallState = .downloading
        await CactusManager.shared.loadModel()
        syncInstallState()
    }

    private func syncInstallState() {
        switch CactusManager.shared.state {
        case .ready:           onDeviceInstallState = .ready
        case .failed:          onDeviceInstallState = .failed
        case .loading:         onDeviceInstallState = .downloading
        case .idle:            onDeviceInstallState = .notInstalled
        }
    }

    static func previewMock() -> AppEnvironment {
        AppEnvironment(route: .mock, onDeviceInstallState: .notInstalled)
    }
}
