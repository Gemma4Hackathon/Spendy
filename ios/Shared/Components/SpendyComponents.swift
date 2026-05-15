import SwiftUI

// MARK: - Shared Card
struct SpendyCard<Content: View>: View {
    let padding: CGFloat
    let content: () -> Content

    init(padding: CGFloat = SpendyTheme.padding,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .cardStyle()
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SpendyTheme.textMuted)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Flat Button
struct GradientButton: View {
    let title: String
    let icon: String?
    let gradient: LinearGradient
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String,
         icon: String? = nil,
         gradient: LinearGradient = SpendyTheme.accentGradient,
         isLoading: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                    Text(title).font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius))
        }
        .disabled(isLoading)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label + (unit.isEmpty ? "" : " · \(unit)"))
                .font(.caption)
                .foregroundStyle(SpendyTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpendyTheme.paddingSm)
        .frame(minHeight: 100)
        .cardStyle()
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SpendyTheme.textMuted)
                .textCase(.uppercase)
                .kerning(0.5)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(color)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Progress Step
struct ProgressStepRow: View {
    let index: Int
    let title: String
    let detail: String
    let state: StepState

    enum StepState {
        case pending
        case active
        case complete
        case failed

        var color: Color {
            switch self {
            case .pending: return SpendyTheme.textMuted
            case .active: return SpendyTheme.accent
            case .complete: return SpendyTheme.healthOK
            case .failed: return SpendyTheme.healthBad
            }
        }

        var icon: String {
            switch self {
            case .pending: return "\(indexPlaceholder)"
            case .active: return "ellipsis"
            case .complete: return "checkmark"
            case .failed: return "xmark"
            }
        }

        private var indexPlaceholder: String { "circle" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(state.color.opacity(state == .pending ? 0.10 : 0.18))
                if state == .pending {
                    Text("\(index)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(state.color)
                } else {
                    Image(systemName: state.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(state.color)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SpendyTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
