import Foundation

enum ServiceError: LocalizedError {
    case notImplemented(String)
    case modelNotReady

    var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return message
        case .modelNotReady:
            return "On-device model is not ready."
        }
    }
}
