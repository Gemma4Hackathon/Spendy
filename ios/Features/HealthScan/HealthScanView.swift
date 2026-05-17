import SwiftUI
import PhotosUI
import UIKit

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
    @State private var showCameraPicker = false

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
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    scanIcon
                    Spacer().frame(height: 40)
                    actionButtons
                    if isProcessing || fallbackMessage != nil {
                        Spacer().frame(height: 20)
                        scanProgressCard
                    }
                    Spacer(minLength: 32)
                    bottomHint
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SpendyTheme.padding)
                .padding(.bottom, 24)
            }
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
        .sheet(isPresented: $showCameraPicker) {
            CameraImagePicker { data in
                Task { await processImageData(data, alreadyPrepared: true) }
            }
            .ignoresSafeArea()
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
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCameraPicker = true
                        } else {
                            scanStage = .failed
                            fallbackMessage = "Camera is not available on this device. Choose an image from your library instead."
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Take Photo").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SpendyTheme.healthOK)
                        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius))
                    }

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
                        .background(SpendyTheme.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius)
                                .stroke(SpendyTheme.border, lineWidth: 1)
                        )
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
                detail: "Trying Gemma 4 vision first; Apple Vision OCR is fallback.",
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
        if let data = try? await item.loadTransferable(type: Data.self) {
            await processImageData(data)
        } else {
            scanStage = .failed
            fallbackMessage = "The selected image could not be read. Try choosing another image."
            selectedItem = nil
        }
    }

    private func processImageData(_ data: Data, alreadyPrepared: Bool = false) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer {
            isProcessing = false
            selectedItem = nil
        }
        fallbackMessage = nil
        scanStage = .readingImage

        let preparedData = alreadyPrepared ? data : (ScanImagePreprocessor.jpegData(from: data) ?? data)
        print("[HealthScan] Prepared image data: original=\(data.count) bytes, prepared=\(preparedData.count) bytes")
        appState.healthScanImageData = preparedData
        do {
            if appEnvironment.route == .onDevice && !appEnvironment.canRunOnDeviceInference {
                scanStage = .failed
                fallbackMessage = "The local model is not ready yet. Wait for model loading to finish, then scan again."
            } else {
                scanStage = .extractingMarkers
                let report = try await appEnvironment.router.healthExtractor.extractHealthReport(imageData: preparedData)
                scanStage = .preparingResults
                appState.setHealthReport(report)
                appState.lastInferenceSource = appEnvironment.router.currentSourceLabel.rawValue
            }
        } catch {
            appEnvironment.markServiceError(error)
            scanStage = .failed
            fallbackMessage = "The scan could not be parsed. Try a sharper photo with the full report visible."
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
            return "Trying Gemma 4 vision first, with Apple Vision OCR as fallback."
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

private enum ScanImagePreprocessor {
    static func jpegData(
        from imageData: Data,
        maxDimension: CGFloat = 1600,
        compressionQuality: CGFloat = 0.82
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return jpegData(from: image, maxDimension: maxDimension, compressionQuality: compressionQuality)
    }

    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = 1600,
        compressionQuality: CGFloat = 0.82
    ) -> Data? {
        autoreleasepool {
            let size = image.size
            let longestSide = max(size.width, size.height)
            guard longestSide > 0 else { return image.jpegData(compressionQuality: compressionQuality) }

            let scale = min(1, maxDimension / longestSide)
            let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return resized.jpegData(compressionQuality: compressionQuality)
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImageData: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageData: (Data) -> Void
        let dismiss: DismissAction

        init(onImageData: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onImageData = onImageData
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard
                let image = info[.originalImage] as? UIImage,
                let data = ScanImagePreprocessor.jpegData(from: image)
            else {
                dismiss()
                return
            }
            print("[HealthScan] Camera image prepared: \(data.count) bytes")
            dismiss()
            DispatchQueue.main.async {
                self.onImageData(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
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
