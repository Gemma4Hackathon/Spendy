import SwiftUI
import PhotosUI

struct HealthScanView: View {
    @Environment(AppState.self) var appState
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isProcessing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var appeared = false
    @State private var navigateToResults = false
    private let service: APIServiceProtocol = MockAPIService()

    var body: some View {
        ZStack {
            SpendyTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                scanIcon
                Spacer().frame(height: 40)
                actionButtons
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
                        Text("Processing...").font(.caption).foregroundStyle(SpendyTheme.healthOK)
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
                 ? "Gemma 4 multimodal extracts your health markers automatically."
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

                    // Demo shortcut
                    GradientButton("Use Demo Data", icon: "sparkles",
                                   gradient: SpendyTheme.accentGradient) {
                        Task { await runDemoExtraction() }
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
        isProcessing = true
        if let data = try? await item.loadTransferable(type: Data.self) {
            appState.healthScanImageData = data
            let report = try? await service.extractHealthReport(imageData: data)
            appState.healthReport = report ?? .demo
        }
        isProcessing = false
        navigateToResults = true
    }

    private func runDemoExtraction() async {
        isProcessing = true
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        appState.healthReport = .demo
        isProcessing = false
        navigateToResults = true
    }

    private func startPulse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pulseScale = 1.12
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack { HealthScanView().environment(s) }
}
