import SwiftUI

struct AddSpendingView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var amountText: String = ""
    @State private var category: SpendingCategory = .food
    @State private var date: Date = Date()
    @State private var note: String = ""

    var amountValid: Bool {
        Double(amountText) != nil && !amountText.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpendyTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SpendyTheme.spacing) {
                        amountField
                        titleField
                        categoryPicker
                        datePicker
                        noteField
                        submitButton
                    }
                    .padding(.horizontal, SpendyTheme.padding)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(SpendyTheme.textMuted)
                }
            }
        }
    }

    // MARK: - Amount
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Amount")
            HStack(alignment: .bottom, spacing: 4) {
                Text("NT$")
                    .font(.title2).fontWeight(.bold).foregroundStyle(SpendyTheme.textMuted)
                    .padding(.bottom, 8)
                TextField("0", text: $amountText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
            }
            Divider().background(SpendyTheme.border)
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Title
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Description")
            TextField("e.g. Coffee, Lunch...", text: $title)
                .font(.body)
                .foregroundStyle(.white)
                .padding(12)
                .background(SpendyTheme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Category Picker
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Category")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: SpendyTheme.paddingSm) {
                ForEach(SpendingCategory.allCases, id: \.self) { cat in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { category = cat }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(category == cat ? .white : Color(hex: cat.colorHex))
                            Text(cat.rawValue).font(.subheadline).lineLimit(1)
                        }
                        .foregroundStyle(category == cat ? .white : SpendyTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            category == cat
                            ? Color(hex: cat.colorHex).opacity(0.2)
                            : SpendyTheme.cardElevated
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm)
                                .stroke(
                                    category == cat
                                    ? Color(hex: cat.colorHex).opacity(0.5)
                                    : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                }
            }
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Date
    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Date")
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Note
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Note (optional)")
            TextField("Add a note...", text: $note, axis: .vertical)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(3)
                .padding(12)
                .background(SpendyTheme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: SpendyTheme.cornerRadiusSm))
        }
        .padding(SpendyTheme.padding)
        .cardStyle()
    }

    // MARK: - Submit
    private var submitButton: some View {
        GradientButton("Add Expense", icon: "plus.circle.fill",
                       gradient: SpendyTheme.financeGradient) {
            guard amountValid, !title.isEmpty else { return }
            let entry = SpendingEntry(
                title: title,
                amount: Double(amountText) ?? 0,
                category: category,
                date: date,
                note: note
            )
            appState.addSpending(entry)
            dismiss()
        }
        .opacity(amountValid && !title.isEmpty ? 1 : 0.4)
    }
}

#Preview {
    let s = AppState(); s.loadDemo()
    return AddSpendingView().environment(s)
}
