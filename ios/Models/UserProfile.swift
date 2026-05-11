import Foundation

// MARK: - User Profile
struct UserProfile: Codable {
    var name: String
    var age: Int
    var gender: String
    var heightCm: Double
    var weightKg: Double
    var goals: [String]
    var lifestyle: String

    var bmi: Double {
        guard heightCm > 0 else { return 0 }
        let h = heightCm / 100
        return weightKg / (h * h)
    }

    var bmiCategory: String {
        switch bmi {
        case ..<18.5:  return "Underweight"
        case 18.5..<24: return "Normal"
        case 24..<27:  return "Overweight"
        default:       return "Obese"
        }
    }

    static let empty = UserProfile(
        name: "", age: 0, gender: "Unspecified",
        heightCm: 0, weightKg: 0, goals: [], lifestyle: ""
    )

    // demo data
    static let demo = UserProfile(
        name: "Alex Chen",
        age: 28,
        gender: "Male",
        heightCm: 175,
        weightKg: 79.2,
        goals: ["Control blood sugar", "Improve sleep quality", "Lose 5 kg"],
        lifestyle: "Office worker with mostly sedentary habits. Frequent takeout, heavy coffee reliance, active nightlife, and high work stress."
    )
}
