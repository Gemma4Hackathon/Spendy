import Foundation

// MARK: - Category
enum SpendingCategory: String, CaseIterable, Codable, Hashable {
    case beverages     = "Sugary Drinks"
    case foodDelivery  = "Food Delivery"
    case food          = "Dining Out"
    case coffee        = "Coffee"
    case entertainment = "Entertainment"
    case lateNight     = "Late Night"
    case other         = "Other"

    var icon: String {
        switch self {
        case .beverages:     return "cup.and.saucer.fill"
        case .foodDelivery:  return "scooter"
        case .food:          return "fork.knife"
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
        case .food:          return "22C55E"
        case .coffee:        return "A855F7"
        case .entertainment: return "3B82F6"
        case .lateNight:     return "6366F1"
        case .other:         return "71717A"
        }
    }
}

// MARK: - Entry
struct SpendingEntry: Identifiable {
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

    // MARK: Demo Data
    static let demoEntries: [SpendingEntry] = [
        SpendingEntry(title: "Bubble Tea (Full Sugar)",      amount: 85,  category: .beverages,     date: daysAgo(0)),
        SpendingEntry(title: "Uber Eats – McDonald's",       amount: 350, category: .foodDelivery,  date: daysAgo(0)),
        SpendingEntry(title: "Starbucks Latte",              amount: 165, category: .coffee,        date: daysAgo(1)),
        SpendingEntry(title: "7-Eleven Late Night Snack",    amount: 120, category: .lateNight,     date: daysAgo(1)),
        SpendingEntry(title: "50 Lan Tea (Full Sugar)",      amount: 65,  category: .beverages,     date: daysAgo(2)),
        SpendingEntry(title: "Foodpanda Fried Chicken",      amount: 280, category: .foodDelivery,  date: daysAgo(2)),
        SpendingEntry(title: "KTV Night Out",                amount: 800, category: .entertainment, date: daysAgo(3)),
        SpendingEntry(title: "Cha Tung Hui Bubble Tea",      amount: 70,  category: .beverages,     date: daysAgo(4)),
        SpendingEntry(title: "Convenience Store Snack",      amount: 95,  category: .lateNight,     date: daysAgo(4)),
        SpendingEntry(title: "Uber Eats – Korean Fried Chicken", amount: 420, category: .foodDelivery, date: daysAgo(5)),
        SpendingEntry(title: "Cha Tung Hui Tea",             amount: 80,  category: .beverages,     date: daysAgo(6)),
        SpendingEntry(title: "Starbucks Caramel Macchiato",  amount: 175, category: .coffee,        date: daysAgo(7)),
        SpendingEntry(title: "Malatang Hotpot Delivery",     amount: 390, category: .foodDelivery,  date: daysAgo(8)),
        SpendingEntry(title: "Milksha Milk Tea",             amount: 90,  category: .beverages,     date: daysAgo(9)),
        SpendingEntry(title: "KTV Weekend",                  amount: 650, category: .entertainment, date: daysAgo(10)),
        SpendingEntry(title: "Starbucks Americano",          amount: 120, category: .coffee,        date: daysAgo(11)),
        SpendingEntry(title: "Late Night Uber Eats",         amount: 310, category: .lateNight,     date: daysAgo(12)),
        SpendingEntry(title: "Bubble Tea (Less Sugar)",      amount: 80,  category: .beverages,     date: daysAgo(13)),
        SpendingEntry(title: "Fried Chicken Rice Box",       amount: 110, category: .food,          date: daysAgo(14)),
        SpendingEntry(title: "Foodpanda Sushi",              amount: 450, category: .foodDelivery,  date: daysAgo(15)),
    ]

    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
