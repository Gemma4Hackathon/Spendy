import Foundation

// MARK: - Category
enum SpendingCategory: String, CaseIterable, Codable, Hashable {
    case beverages     = "Sugary Drinks"
    case foodDelivery  = "Food Delivery"
    case fastFood      = "Fast Food"
    case food          = "Dining Out"
    case convenienceStore = "Convenience Store"
    case groceries     = "Groceries"
    case coffee        = "Coffee"
    case entertainment = "Entertainment"
    case lateNight     = "Late Night"
    case other         = "Other"

    var icon: String {
        switch self {
        case .beverages:     return "cup.and.saucer.fill"
        case .foodDelivery:  return "scooter"
        case .fastFood:      return "takeoutbag.and.cup.and.straw.fill"
        case .food:          return "fork.knife"
        case .convenienceStore: return "cart.fill"
        case .groceries:     return "basket.fill"
        case .coffee:        return "mug.fill"
        case .entertainment: return "music.mic"
        case .lateNight:     return "moon.fill"
        case .other:         return "bag.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .beverages:     return "F59E0B"
        case .foodDelivery:  return "EF4444"
        case .fastFood:      return "FB7185"
        case .food:          return "22C55E"
        case .convenienceStore: return "14B8A6"
        case .groceries:     return "84CC16"
        case .coffee:        return "A855F7"
        case .entertainment: return "3B82F6"
        case .lateNight:     return "6366F1"
        case .other:         return "71717A"
        }
    }
}

// MARK: - Entry
struct SpendingEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var category: SpendingCategory
    var date: Date
    var note: String

    init(id: UUID = UUID(),
         title: String,
         amount: Double,
         category: SpendingCategory,
         date: Date = Date(),
         note: String = "") {
        self.id       = id
        self.title    = title
        self.amount   = amount
        self.category = category
        self.date     = date
        self.note     = note
    }

    // MARK: - Month helper
    func isInMonth(_ referenceDate: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
    }

    // MARK: Demo Data
    static let demoMainMonth: Date = demoDate(month: 5, day: 16)

    static let demoEntries: [SpendingEntry] = [
        SpendingEntry(title: "McDonald's Big Mac Meal", amount: 185, category: .fastFood, date: demoDate(month: 5, day: 16)),
        SpendingEntry(title: "Bubble Tea (Full Sugar)", amount: 85, category: .beverages, date: demoDate(month: 5, day: 16)),
        SpendingEntry(title: "Uber Eats Fried Chicken", amount: 420, category: .foodDelivery, date: demoDate(month: 5, day: 15)),
        SpendingEntry(title: "Starbucks Latte", amount: 165, category: .coffee, date: demoDate(month: 5, day: 14)),
        SpendingEntry(title: "7-Eleven Late Snack", amount: 120, category: .convenienceStore, date: demoDate(month: 5, day: 13)),
        SpendingEntry(title: "Foodpanda Sushi", amount: 450, category: .foodDelivery, date: demoDate(month: 5, day: 12)),
        SpendingEntry(title: "KTV Night Out", amount: 800, category: .entertainment, date: demoDate(month: 5, day: 11)),
        SpendingEntry(title: "50 Lan Tea (Full Sugar)", amount: 65, category: .beverages, date: demoDate(month: 5, day: 10)),
        SpendingEntry(title: "Late Night Uber Eats", amount: 310, category: .lateNight, date: demoDate(month: 5, day: 9)),
        SpendingEntry(title: "FamilyMart Snacks", amount: 95, category: .convenienceStore, date: demoDate(month: 5, day: 8)),
        SpendingEntry(title: "Foodpanda Fried Chicken", amount: 280, category: .foodDelivery, date: demoDate(month: 5, day: 7)),
        SpendingEntry(title: "Grocery Meal Prep", amount: 520, category: .groceries, date: demoDate(month: 5, day: 6)),
        SpendingEntry(title: "Coffee Before Meeting", amount: 120, category: .coffee, date: demoDate(month: 5, day: 5)),
        SpendingEntry(title: "Burger King Combo", amount: 210, category: .fastFood, date: demoDate(month: 5, day: 4)),

        SpendingEntry(title: "Foodpanda Hotpot", amount: 390, category: .foodDelivery, date: demoDate(month: 4, day: 26)),
        SpendingEntry(title: "McDonald's Breakfast", amount: 145, category: .fastFood, date: demoDate(month: 4, day: 24)),
        SpendingEntry(title: "Bubble Tea", amount: 80, category: .beverages, date: demoDate(month: 4, day: 23)),
        SpendingEntry(title: "Supermarket Vegetables", amount: 460, category: .groceries, date: demoDate(month: 4, day: 21)),
        SpendingEntry(title: "Starbucks Americano", amount: 120, category: .coffee, date: demoDate(month: 4, day: 18)),
        SpendingEntry(title: "Movie Night", amount: 520, category: .entertainment, date: demoDate(month: 4, day: 16)),
        SpendingEntry(title: "7-Eleven Late Dinner", amount: 155, category: .convenienceStore, date: demoDate(month: 4, day: 13)),
        SpendingEntry(title: "Ramen Dinner", amount: 260, category: .food, date: demoDate(month: 4, day: 9)),
        SpendingEntry(title: "Late Night Fried Chicken", amount: 330, category: .lateNight, date: demoDate(month: 4, day: 6)),

        SpendingEntry(title: "KFC Combo", amount: 220, category: .fastFood, date: demoDate(month: 3, day: 28)),
        SpendingEntry(title: "Uber Eats Thai Food", amount: 360, category: .foodDelivery, date: demoDate(month: 3, day: 25)),
        SpendingEntry(title: "Milk Tea", amount: 75, category: .beverages, date: demoDate(month: 3, day: 22)),
        SpendingEntry(title: "Grocery Chicken Breast", amount: 380, category: .groceries, date: demoDate(month: 3, day: 20)),
        SpendingEntry(title: "Coffee Shop", amount: 150, category: .coffee, date: demoDate(month: 3, day: 17)),
        SpendingEntry(title: "Convenience Store Snacks", amount: 130, category: .convenienceStore, date: demoDate(month: 3, day: 14)),
        SpendingEntry(title: "BBQ Dinner", amount: 520, category: .food, date: demoDate(month: 3, day: 11)),
        SpendingEntry(title: "Concert Ticket", amount: 900, category: .entertainment, date: demoDate(month: 3, day: 7)),
        SpendingEntry(title: "Late Night Noodles", amount: 180, category: .lateNight, date: demoDate(month: 3, day: 3)),

        SpendingEntry(title: "Burger King Meal", amount: 205, category: .fastFood, date: demoDate(month: 2, day: 27)),
        SpendingEntry(title: "Food Delivery Pasta", amount: 340, category: .foodDelivery, date: demoDate(month: 2, day: 24)),
        SpendingEntry(title: "Bubble Tea", amount: 90, category: .beverages, date: demoDate(month: 2, day: 22)),
        SpendingEntry(title: "Grocery Fruit", amount: 310, category: .groceries, date: demoDate(month: 2, day: 19)),
        SpendingEntry(title: "Coffee", amount: 135, category: .coffee, date: demoDate(month: 2, day: 15)),
        SpendingEntry(title: "FamilyMart Bento", amount: 115, category: .convenienceStore, date: demoDate(month: 2, day: 12)),
        SpendingEntry(title: "Dinner With Friends", amount: 680, category: .food, date: demoDate(month: 2, day: 9)),
        SpendingEntry(title: "Arcade Night", amount: 430, category: .entertainment, date: demoDate(month: 2, day: 6)),
        SpendingEntry(title: "Late Night Delivery", amount: 290, category: .lateNight, date: demoDate(month: 2, day: 2)),

        SpendingEntry(title: "McDonald's Fries", amount: 95, category: .fastFood, date: demoDate(month: 1, day: 29)),
        SpendingEntry(title: "Uber Eats Burger", amount: 360, category: .foodDelivery, date: demoDate(month: 1, day: 26)),
        SpendingEntry(title: "Sugary Lemon Tea", amount: 70, category: .beverages, date: demoDate(month: 1, day: 23)),
        SpendingEntry(title: "Grocery Meal Prep", amount: 480, category: .groceries, date: demoDate(month: 1, day: 20)),
        SpendingEntry(title: "Latte", amount: 160, category: .coffee, date: demoDate(month: 1, day: 17)),
        SpendingEntry(title: "7-Eleven Snacks", amount: 125, category: .convenienceStore, date: demoDate(month: 1, day: 14)),
        SpendingEntry(title: "Hotpot Dinner", amount: 620, category: .food, date: demoDate(month: 1, day: 10)),
        SpendingEntry(title: "Movie Ticket", amount: 350, category: .entertainment, date: demoDate(month: 1, day: 6)),
        SpendingEntry(title: "Late Night Noodles", amount: 180, category: .lateNight, date: demoDate(month: 1, day: 3)),
    ]

    private static func demoDate(month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = 12
        return components.date ?? Date()
    }
}
