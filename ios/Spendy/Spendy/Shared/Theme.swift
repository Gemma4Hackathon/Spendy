import SwiftUI

// MARK: - Design System
enum SpendyTheme {

    // MARK: Colors – neutral gray palette (Linear / Notion aesthetic)
    static let background   = Color(hex: "0F0F0F")   // near-black neutral
    static let card         = Color(hex: "191919")   // card surface
    static let cardElevated = Color(hex: "232323")   // elevated surface
    static let border       = Color.white.opacity(0.06)

    // Single accent – clean blue, no purple
    static let accent       = Color(hex: "4F80FF")
    static let accentEnd    = Color(hex: "4F80FF")   // flat, same color

    static let healthOK     = Color(hex: "22C55E")   // green-500
    static let healthWarn   = Color(hex: "EAB308")   // yellow-500
    static let healthBad    = Color(hex: "EF4444")   // red-500
    static let finance      = Color(hex: "3B82F6")   // blue-500

    static let textPrimary  = Color.white
    static let textMuted    = Color(hex: "71717A")   // zinc-500, neutral gray

    // MARK: "Gradients" – all flat (single color, no actual gradient)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var financeGradient: LinearGradient {
        LinearGradient(colors: [finance, finance],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var healthGradient: LinearGradient {
        LinearGradient(colors: [healthOK, healthOK],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var warnGradient: LinearGradient {
        LinearGradient(colors: [healthWarn, healthWarn],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Layout
    static let cornerRadius: CGFloat   = 14
    static let cornerRadiusSm: CGFloat = 9
    static let padding: CGFloat        = 20
    static let paddingSm: CGFloat      = 14
    static let spacing: CGFloat        = 20
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - View Helpers
extension View {
    func cardStyle() -> some View {
        self
            .background(SpendyTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SpendyTheme.cornerRadius)
                    .stroke(SpendyTheme.border, lineWidth: 1)
            )
    }

    func spendyBackground() -> some View {
        self.background(SpendyTheme.background.ignoresSafeArea())
    }
}
