// swift-tools-version: 6.0
import PackageDescription

// Unit tests for the pure on-device logic (JSON repair, health-value verification, prompt
// trimming, output guardrails, spending targets). The app compiles the same files through the
// Xcode project; this package only lets `swift test` run them on the Mac without touching the
// project file. Run from the repo root: `swift test`.
let package = Package(
    name: "SpendyCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SpendyCore",
            path: "ios",
            sources: [
                "Models/HealthReport.swift",
                "Services/Providers/OnDevice/LenientJSON.swift",
                "Services/Providers/OnDevice/HealthReportVerifier.swift",
                "Services/Providers/OnDevice/SpendingTargets.swift",
                "Services/Providers/OnDevice/OCRPromptBuilder.swift",
            ]
        ),
        .testTarget(
            name: "SpendyCoreTests",
            dependencies: ["SpendyCore"],
            path: "Tests/SpendyCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
