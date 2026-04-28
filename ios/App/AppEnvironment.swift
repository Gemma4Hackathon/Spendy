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
        set { router.route = newValue }
    }

    var canRunOnDeviceInference: Bool {
        route == .onDevice && onDeviceInstallState == .ready
    }

    func markServiceError(_ error: Error) {
        lastServiceErrorMessage = error.localizedDescription
    }

    static func previewMock() -> AppEnvironment {
        AppEnvironment(route: .mock, onDeviceInstallState: .notInstalled)
    }
}
