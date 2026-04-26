import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) var appState
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpendyTheme.spacing) {
                avatarRow
                statsRow
                goalsSection
                demoSection
                lifestyleSection
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .spendyBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }

    // MARK: - Avatar Row
    private var avatarRow: some View {
        HStack(spacing: 14) {
            ZStack {
                SpendyTheme.accent
                Text(initials)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.profile.name.isEmpty ? "Set your name" : appState.profile.name)
                    .font(.title3).fontWeight(.semibold).foregroundStyle(.white)
                HStack(spacing: 6) {
                    if !appState.profile.gender.isEmpty {
                        Text(appState.profile.gender).foregroundStyle(SpendyTheme.textMuted)
                    }
                    if appState.profile.age > 0 {
                        Text("·").foregroundStyle(SpendyTheme.textMuted)
                        Text("\(appState.profile.age) years old").foregroundStyle(SpendyTheme.textMuted)
                    }
                }
                .font(.subheadline)

                if appState.isDemoLoaded {
                    StatusBadge(label: "Demo Mode", color: SpendyTheme.accent)
                }
            }
            Spacer()
        }
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: - Stats Horizontal Row
    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statPill(
                    label: "Height",
                    value: appState.profile.heightCm > 0 ? "\(Int(appState.profile.heightCm))" : "--",
                    unit: "cm", icon: "ruler", color: SpendyTheme.accent)
                statPill(
                    label: "Weight",
                    value: appState.profile.weightKg > 0 ? String(format: "%.1f", appState.profile.weightKg) : "--",
                    unit: "kg", icon: "scalemass.fill", color: SpendyTheme.finance)
                statPill(
                    label: "BMI",
                    value: appState.profile.bmi > 0 ? String(format: "%.1f", appState.profile.bmi) : "--",
                    unit: appState.profile.bmiCategory, icon: "figure.stand", color: bmiColor)
                statPill(
                    label: "Goals",
                    value: "\(appState.profile.goals.count)",
                    unit: "set", icon: "target", color: SpendyTheme.healthOK)
            }
            .padding(.horizontal, SpendyTheme.padding)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.easeOut(duration: 0.4).delay(0.06), value: appeared)
    }

    private func statPill(label: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(unit.isEmpty ? label : "\(label) · \(unit)")
                .font(.caption2)
                .foregroundStyle(SpendyTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: 96, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Goals
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Health Goals")
            if appState.profile.goals.isEmpty {
                Text("No health goals set.")
                    .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.profile.goals, id: \.self) { goal in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(SpendyTheme.healthOK)
                            Text(goal).font(.subheadline).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.12), value: appeared)
    }

    // MARK: - Demo
    private var demoSection: some View {
        VStack(spacing: SpendyTheme.paddingSm) {
            if !appState.isDemoLoaded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Load Demo").font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                    Text("Populate a full health + spending scenario to explore Spendy's cross-domain analysis.")
                        .font(.caption).foregroundStyle(SpendyTheme.textMuted)
                }
                GradientButton("Load Demo", icon: "sparkles") {
                    withAnimation(.spring(duration: 0.4)) { appState.loadDemo() }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(SpendyTheme.healthOK)
                    Text("Demo loaded").font(.subheadline).foregroundStyle(SpendyTheme.healthOK)
                    Spacer()
                    Button("Clear") { withAnimation { appState.clearAll() } }
                        .font(.subheadline).foregroundStyle(SpendyTheme.textMuted)
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.16), value: appeared)
    }

    // MARK: - Lifestyle
    private var lifestyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Lifestyle")
            Text(appState.profile.lifestyle.isEmpty
                 ? "No lifestyle notes set."
                 : appState.profile.lifestyle)
                .font(.subheadline)
                .foregroundStyle(appState.profile.lifestyle.isEmpty ? SpendyTheme.textMuted : .white.opacity(0.88))
                .lineSpacing(4)
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
        .padding(.horizontal, SpendyTheme.padding)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
    }

    // MARK: - Helpers
    private var initials: String {
        let n = appState.profile.name
        guard !n.isEmpty else { return "?" }
        let parts = n.components(separatedBy: " ")
        return parts.count >= 2
            ? String(parts[0].prefix(1)) + String(parts[1].prefix(1))
            : String(n.prefix(1))
    }

    private var bmiColor: Color {
        switch appState.profile.bmiCategory {
        case "Normal":      return SpendyTheme.healthOK
        case "Overweight":  return SpendyTheme.healthWarn
        case "Obese":       return SpendyTheme.healthBad
        default:            return SpendyTheme.textMuted
        }
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return NavigationStack { ProfileView().environment(s) }
}
