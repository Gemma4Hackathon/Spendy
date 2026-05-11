import SwiftUI

// MARK: - Body Visualization Card
// Generates a before/after body silhouette infographic using Gemini image generation.
// Only non-sensitive data (BMI, age, gender, goals) is sent — NO real name or blood values.
struct BodyVisualizationCard: View {
    let profile: UserProfile
    let result: InsightResult

    @State private var state: CardState = .idle
    @State private var beforeImageData: Data? = nil
    @State private var afterImageData: Data? = nil

    enum CardState {
        case idle, generating, done, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    SpendyTheme.finance.opacity(0.15)
                    Image(systemName: "figure.stand.line.dotted.figure.stand")
                        .foregroundStyle(SpendyTheme.finance)
                        .font(.system(size: 16))
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Transformation Preview")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                    Text("AI-estimated: current vs. 3-month goal")
                        .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                }
                Spacer()
                StatusBadge(label: "Gemini", color: SpendyTheme.finance)
            }

            switch state {
            case .idle:
                idleContent
            case .generating:
                generatingContent
            case .done:
                imageContent
            case .failed(let msg):
                errorContent(msg)
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - States

    private var idleContent: some View {
        VStack(spacing: 12) {
            Text("Generate a visual preview of your estimated body shape now vs. your 3-month health goal based on the AI recommendations above.")
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Privacy note
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.caption2)
                Text("Only sends: age, gender, BMI, goals — never your name or blood values.")
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(SpendyTheme.textMuted)
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))

            GradientButton("Generate Preview", icon: "sparkles",
                           gradient: SpendyTheme.financeGradient) {
                Task { await generate() }
            }
        }
    }

    private var generatingContent: some View {
        VStack(spacing: 14) {
            ProgressView().tint(SpendyTheme.finance).scaleEffect(1.3)
            Text("Gemini is generating your body visualization...")
                .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                .multilineTextAlignment(.center)
            Text("This may take 10–20 seconds")
                .font(.caption2).foregroundStyle(SpendyTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var imageContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Before
                imagePanel(data: beforeImageData, label: "NOW", color: SpendyTheme.healthWarn)
                // After
                imagePanel(data: afterImageData, label: "3-MONTH GOAL", color: SpendyTheme.healthOK)
            }
            Text("For behavioral guidance only. Not a medical prediction.")
                .font(.caption2).foregroundStyle(SpendyTheme.textMuted)
                .multilineTextAlignment(.center)

            Button {
                state = .idle
                beforeImageData = nil
                afterImageData = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                    Text("Regenerate").font(.caption)
                }
                .foregroundStyle(SpendyTheme.textMuted)
            }
        }
    }

    @ViewBuilder
    private func imagePanel(data: Data?, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            if let d = data, let uiImg = UIImage(data: d) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
            } else {
                RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 160)
                    .overlay(
                        ProgressView().tint(color)
                    )
            }
            Text(label)
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(color)
                .textCase(.uppercase).kerning(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorContent(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SpendyTheme.healthBad).font(.title3)
            Text(msg)
                .font(.caption).foregroundStyle(SpendyTheme.healthBad)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { state = .idle }
                .font(.subheadline).foregroundStyle(SpendyTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Generate
    private func generate() async {
        state = .generating

        let bmi = String(format: "%.1f", profile.bmi)
        let category = profile.bmiCategory
        let goals = profile.goals.prefix(3).joined(separator: ", ")
        let riskScore = result.overallRiskScore

        let beforePrompt = """
        Medical infographic style illustration. A simple body silhouette of a \(profile.age)-year-old \
        \(profile.gender.lowercased()), BMI \(bmi) (\(category)), with visual indicators of \
        health risk score \(riskScore)/100. Minimal flat design, dark background, \
        clinical annotation style. Label: "CURRENT STATUS". Single figure only.
        """

        let afterPrompt = """
        Medical infographic style illustration. A simple body silhouette of a \(profile.age)-year-old \
        \(profile.gender.lowercased()), BMI slightly improved, healthy posture, \
        after achieving goals: \(goals.isEmpty ? "improve health" : goals). \
        Minimal flat design, dark background, clinical annotation style, \
        green accent glow. Label: "3-MONTH GOAL". Single figure only.
        """

        // Generate both in parallel
        async let before = try? GeminiAPI.imageGenerate(prompt: beforePrompt)
        async let after  = try? GeminiAPI.imageGenerate(prompt: afterPrompt)
        let (b, a) = await (before, after)

        if b == nil && a == nil {
            state = .failed("Image generation failed. Make sure your API key supports Gemini image generation (gemini-2.0-flash-preview-image-generation).")
        } else {
            beforeImageData = b
            afterImageData  = a
            state = .done
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return ScrollView {
        BodyVisualizationCard(profile: s.profile, result: s.insightResult ?? .demo)
            .padding()
    }
    .background(SpendyTheme.background)
}
