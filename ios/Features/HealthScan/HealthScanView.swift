import SwiftUI
import PhotosUI

struct HealthScanView: View {
    @Environment(AppState.self) var appState
    @Environment(AppEnvironment.self) var appEnvironment
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isProcessing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var appeared = false
    @State private var navigateToResults = false
    @State private var scanStage: ScanStage = .idle
    @State private var fallbackMessage: String? = nil

    private enum ScanStage {
        case idle
        case readingImage
        case extractingMarkers
        case preparingResults
        case failed
    }

    var body: some View {
        ZStack {
            SpendyTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                scanIcon
                Spacer().frame(height: 40)
                actionButtons
                if isProcessing || fallbackMessage != nil {
                    Spacer().frame(height: 20)
                    scanProgressCard
                }
                Spacer()
                bottomHint
            }
            .padding(.horizontal, SpendyTheme.padding)
        }
        .navigationTitle("Health Scan")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToResults) {
            HealthResultsView()
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await processItem(newItem) }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            startPulse()
        }
    }

    // MARK: - Scan Icon
    private var scanIcon: some View {
        ZStack {
            // Pulse rings
            ForEach(0..<3) { i in
                Circle()
                    .stroke(SpendyTheme.healthOK.opacity(0.10 - Double(i) * 0.025))
                    .frame(width: 130 + CGFloat(i) * 45,
                           height: 130 + CGFloat(i) * 45)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(Double(i) * 0.4),
                        value: pulseScale
                    )
            }

            // Core circle
            ZStack {
                Circle()
                    .fill(SpendyTheme.healthOK.opacity(0.10))
                    .frame(width: 120, height: 120)

                if isProcessing {
                    VStack(spacing: 10) {
                        ProgressView().tint(SpendyTheme.healthOK).scaleEffect(1.3)
                        Text(scanStageTitle).font(.caption).foregroundStyle(SpendyTheme.healthOK)
                    }
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(SpendyTheme.healthOK)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.5), value: appeared)
    }

    // MARK: - Buttons
    private var actionButtons: some View {
        VStack(spacing: 14) {
            Text(isProcessing ? "Parsing your report..." : "Upload a Health Report")
                .font(.title3).fontWeight(.semibold).foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(isProcessing
                 ? scanStageDescription
                 : "Take a photo or choose a blood test or checkup report from your library.")
                .font(.subheadline)
                .foregroundStyle(SpendyTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if !isProcessing {
                VStack(spacing: 12) {
                    // Photo Library
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Choose from Library").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SpendyTheme.healthOK)
                        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius))
                    }

                }
            }

            // Already has results
            if appState.hasHealthData && !isProcessing {
                Button {
                    navigateToResults = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(SpendyTheme.healthOK)
                        Text("View Parsed Report").font(.subheadline).foregroundStyle(SpendyTheme.healthOK)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(SpendyTheme.textMuted)
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.45).delay(0.1), value: appeared)
    }

    private var scanProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Scan Progress", subtitle: "Local image extraction")
            ProgressStepRow(
                index: 1,
                title: "Read image",
                detail: "Preparing the selected report photo.",
                state: stepState(for: .readingImage)
            )
            ProgressStepRow(
                index: 2,
                title: "Extract markers",
                detail: "Gemma 4 reads health values and reference ranges.",
                state: stepState(for: .extractingMarkers)
            )
            ProgressStepRow(
                index: 3,
                title: "Prepare results",
                detail: "Formatting metrics and evidence trace for review.",
                state: stepState(for: .preparingResults)
            )

            if let message = fallbackMessage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(SpendyTheme.healthWarn)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        fallbackMessage = nil
                        scanStage = .idle
                    } label: {
                        Text("Try another image")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(SpendyTheme.healthOK)
                    }
                }
                .padding(12)
                .insetSurface()
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Bottom Hint
    private var bottomHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill").font(.caption)
            Text("Processed on-device. Never uploaded.").font(.caption)
        }
        .foregroundStyle(SpendyTheme.textMuted)
        .padding(.bottom, 24)
    }

    // MARK: - Logic
    private func processItem(_ item: PhotosPickerItem) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer {
            isProcessing = false
            selectedItem = nil
        }
        fallbackMessage = nil
        scanStage = .readingImage
        if let data = try? await item.loadTransferable(type: Data.self) {
            appState.healthScanImageData = data
            do {
                if appEnvironment.route == .onDevice && !appEnvironment.canRunOnDeviceInference {
                    scanStage = .failed
                    fallbackMessage = "The local model is not ready yet. Wait for model loading to finish, then scan again."
                } else {
                    scanStage = .extractingMarkers
                    let report = try await appEnvironment.router.healthExtractor.extractHealthReport(imageData: data)
                    scanStage = .preparingResults
                    appState.setHealthReport(report)
                    appState.lastInferenceSource = appEnvironment.router.currentSourceLabel.rawValue
                }
            } catch {
                appEnvironment.markServiceError(error)
                scanStage = .failed
                fallbackMessage = "The scan could not be parsed. Try a sharper photo with the full report visible."
            }
        } else {
            scanStage = .failed
            fallbackMessage = "The selected image could not be read. Try choosing another image."
        }
        if fallbackMessage == nil {
            scanStage = .preparingResults
            navigateToResults = true
        }
    }

    private func startPulse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pulseScale = 1.12
        }
    }

    private var scanStageTitle: String {
        switch scanStage {
        case .idle: return "Ready"
        case .readingImage: return "Reading image"
        case .extractingMarkers: return "Extracting markers"
        case .preparingResults: return "Preparing results"
        case .failed: return "Review needed"
        }
    }

    private var scanStageDescription: String {
        switch scanStage {
        case .idle:
            return "Take a photo or choose a blood test or checkup report from your library."
        case .readingImage:
            return "Preparing the report image for local processing."
        case .extractingMarkers:
            return "Gemma 4 multimodal is extracting health markers on this iPhone."
        case .preparingResults:
            return "Formatting extracted values and evidence trace."
        case .failed:
            return "Review the message below and try a sharper full-page image."
        }
    }

    private func stepState(for step: ScanStage) -> ProgressStepRow.StepState {
        if scanStage == .failed {
            return step == .preparingResults ? .failed : .complete
        }
        switch (scanStage, step) {
        case (.idle, _):
            return .pending
        case (.readingImage, .readingImage),
             (.extractingMarkers, .extractingMarkers),
             (.preparingResults, .preparingResults):
            return .active
        case (.extractingMarkers, .readingImage),
             (.preparingResults, .readingImage),
             (.preparingResults, .extractingMarkers):
            return .complete
        default:
            return .pending
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack {
        HealthScanView()
            .environment(s)
            .environment(AppEnvironment.previewMock())
    }
}
