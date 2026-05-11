import SwiftUI

struct EditProfileView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    // Local draft – committed only on Save
    @State private var name: String       = ""
    @State private var age: String        = ""
    @State private var gender: String     = "Male"
    @State private var heightCm: String   = ""
    @State private var weightKg: String   = ""
    @State private var goalsText: String  = ""   // comma-separated input
    @State private var lifestyle: String  = ""

    private let genderOptions = ["Male", "Female", "Non-binary", "Prefer not to say"]

    var body: some View {
        NavigationStack {
            ZStack {
                SpendyTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SpendyTheme.spacing) {
                        basicSection
                        physicalSection
                        goalsSection
                        lifestyleSection
                        saveButton
                    }
                    .padding(.horizontal, SpendyTheme.padding)
                    .padding(.top, 16)
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SpendyTheme.textMuted)
                }
            }
            .onAppear { populateDraft() }
        }
    }

    // MARK: - Basic Info
    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Basic Info")

            fieldRow(label: "Name", placeholder: "Your name") {
                TextField("e.g. Alex Chen", text: $name)
                    .foregroundStyle(.white)
            }

            fieldRow(label: "Age", placeholder: "") {
                TextField("28", text: $age)
                    .keyboardType(.numberPad)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Gender")
                    .font(.caption)
                    .foregroundStyle(SpendyTheme.textMuted)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Picker("Gender", selection: $gender) {
                    ForEach(genderOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Physical Stats
    private var physicalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Physical Stats")

            HStack(spacing: 12) {
                fieldRow(label: "Height (cm)", placeholder: "175") {
                    TextField("175", text: $heightCm)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(.white)
                }
                fieldRow(label: "Weight (kg)", placeholder: "70") {
                    TextField("70.0", text: $weightKg)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(.white)
                }
            }

            // Live BMI preview
            if let h = Double(heightCm), let w = Double(weightKg), h > 0 {
                let bmi = w / ((h / 100) * (h / 100))
                HStack(spacing: 8) {
                    Image(systemName: "figure.stand")
                        .foregroundStyle(SpendyTheme.accent)
                    Text("Estimated BMI: \(String(format: "%.1f", bmi))")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text(bmiCategory(bmi))
                        .font(.caption)
                        .foregroundStyle(bmiColor(bmi))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(bmiColor(bmi).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Health Goals
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Health Goals", subtitle: "Separate with commas")
            TextField("Lose 5 kg, Control blood sugar, Improve sleep...", text: $goalsText, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(4)
                .padding(12)
                .background(SpendyTheme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Lifestyle
    private var lifestyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Lifestyle", subtitle: "Brief description of your daily habits")
            TextField("Office worker, frequent takeout, high coffee intake...", text: $lifestyle, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(5)
                .padding(12)
                .background(SpendyTheme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Save Button
    private var saveButton: some View {
        GradientButton("Save Profile", icon: "checkmark.circle.fill") {
            commitDraft()
            dismiss()
        }
        .opacity(name.isEmpty ? 0.4 : 1.0)
        .disabled(name.isEmpty)
    }

    // MARK: - Helpers
    @ViewBuilder
    private func fieldRow<Content: View>(label: String, placeholder: String,
                                         @ViewBuilder field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
                .textCase(.uppercase)
                .kerning(0.5)
            field()
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SpendyTheme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        }
    }

    private func populateDraft() {
        let p = appState.profile
        name      = p.name
        age       = p.age > 0 ? "\(p.age)" : ""
        gender    = p.gender.isEmpty ? "Male" : p.gender
        heightCm  = p.heightCm > 0 ? "\(Int(p.heightCm))" : ""
        weightKg  = p.weightKg > 0 ? String(format: "%.1f", p.weightKg) : ""
        goalsText = p.goals.joined(separator: ", ")
        lifestyle = p.lifestyle
    }

    private func commitDraft() {
        let goals = goalsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        appState.profile = UserProfile(
            name:      name,
            age:       Int(age) ?? 0,
            gender:    gender,
            heightCm:  Double(heightCm) ?? 0,
            weightKg:  Double(weightKg) ?? 0,
            goals:     goals,
            lifestyle: lifestyle
        )
        appState.isDemoLoaded = false
        appState.saveToDisk()
    }

    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5:  return "Underweight"
        case 18.5..<24: return "Normal"
        case 24..<27:  return "Overweight"
        default:       return "Obese"
        }
    }

    private func bmiColor(_ bmi: Double) -> Color {
        switch bmi {
        case 18.5..<24: return SpendyTheme.healthOK
        case 24..<27:   return SpendyTheme.healthWarn
        default:        return SpendyTheme.healthBad
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return EditProfileView().environment(s)
}
