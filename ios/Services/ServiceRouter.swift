import Foundation

enum InferenceRoute: String, CaseIterable {
    case mock
    case remote
    case onDevice
}

enum InferenceSourceLabel: String {
    case mock = "Mock"
    case remote = "Remote"
    case onDevice = "On-device"
}

final class ServiceRouter {
    var route: InferenceRoute

    private let mockFinance = MockFinanceSummaryProvider()
    private let mockHealth = MockHealthReportExtractor()
    private let mockInsight = MockInsightGenerator()

    private let remoteFinance = RemoteFinanceSummaryProvider()
    private let remoteHealth = RemoteHealthReportExtractor()
    private let remoteInsight = RemoteInsightGenerator()

    private let onDeviceFinance = OnDeviceFinanceSummaryProvider()
    private let onDeviceHealth = OnDeviceHealthReportExtractor()
    private let onDeviceInsight = OnDeviceInsightGenerator()

    init(route: InferenceRoute = .mock) {
        self.route = route
    }

    var financeProvider: FinanceSummaryProviding {
        switch route {
        case .mock: return mockFinance
        case .remote: return remoteFinance
        case .onDevice: return onDeviceFinance
        }
    }

    var healthExtractor: HealthReportExtracting {
        switch route {
        case .mock: return mockHealth
        case .remote: return remoteHealth
        case .onDevice: return onDeviceHealth
        }
    }

    var insightGenerator: InsightGenerating {
        switch route {
        case .mock: return mockInsight
        case .remote: return remoteInsight
        case .onDevice: return onDeviceInsight
        }
    }

    var currentSourceLabel: InferenceSourceLabel {
        switch route {
        case .mock: return .mock
        case .remote: return .remote
        case .onDevice: return .onDevice
        }
    }

    var supportsLocalModelTasks: Bool {
        route == .onDevice
    }
}
