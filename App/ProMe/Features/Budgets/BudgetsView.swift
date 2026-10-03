import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Monthly budget per category with live progress and over-budget flags.
struct BudgetsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [BudgetService.Row] = []
    @State private var monthOffset = 0
    @State private var editing: BudgetService.Row?
    @State private var showPicker = false
    @State private var categories: [CategoryMO] = []

    private var monthStart: Date {
        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        let month = resolver.monthContaining(.now)
        let shifted = resolver.calendar.date(byAdding: .month, value: monthOffset, to: month.start) ?? month.start
        return shifted
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "gauge.with.needle",
                    title: String(localized: "No Budgets This Month"),
                    detail: String(localized: "Set a monthly limit per category to track spending.")
                )
            } else {
                List {
                    ForEach(rows) { row in
                        rowView(row)
                            .contextMenu {
                                Button(String(localized: "Edit")) { editing = row }
                            }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Budgets"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    monthOffset -= 1
                    reload()
                } label: { Image(systemName: "chevron.left") }
                Text(monthLabel)
                    .font(.appCallout.monospacedDigit())
                    .frame(minWidth: 76)
                Button {
                    monthOffset += 1
                    reload()
                } label: { Image(systemName: "chevron.right") }
                .disabled(monthOffset >= 0)

                Button { showPicker = true } label: {
                    Label(String(localized: "Add Budget"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showPicker, onDismiss: { reload() }) {
            BudgetPicker(categories: expenseCategories) { category in
                setBudget(category: category)
            }
            .frame(minWidth: 380, minHeight: 220)
        }
        .sheet(item: $editing, onDismiss: { reload() }) { row in
            BudgetEditor(row: row) { category, amountText in
                updateBudget(category: category, amountText: amountText)
            }
            .frame(minWidth: 380, minHeight: 220)
        }
    }

    private var monthLabel: String {
        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        return resolver.monthLabel(forMonthStart: monthStart)
    }

    private var expenseCategories: [CategoryMO] {
        (try? appModel.services?.categories.allCategories(kind: .expense)) ?? []
    }

    private func rowView(_ row: BudgetService.Row) -> some View {
        let over = row.fractionUsed > 1
        return HStack(spacing: 12) {
            Text(row.entry.category?.name ?? "—")
                .font(.appBody.weight(.medium))
                .frame(width: 150, alignment: .leading)
            ProgressView(value: min(row.fractionUsed, 1.0))
                .progressViewStyle(.linear)
                .tint(over ? ProMeColor.expense : (row.fractionUsed > 0.8 ? .orange : ProMeColor.income))
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(row.fractionUsed * 100))%")
                    .font(.appCaption.monospacedDigit())
                    .foregroundStyle(over ? ProMeColor.expense : .secondary)
                HStack(spacing: 4) {
                    Text(Format.amount(row.spentMinor, code: row.entry.currencyCode))
                        .foregroundStyle(.secondary)
                    Text("·")
                    Text(Format.amount(row.entry.amountMinor, code: row.entry.currencyCode))
                }
                .font(.appCaption.monospacedDigit())
            }
            .frame(width: 200, alignment: .trailing)
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        let end = resolver.calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        rows = (try? services.budgets.rows(
            monthKey: BudgetService.monthKey(for: monthStart, preference: AppPreferences.calendar),
            scope: appModel.activeScope,
            from: monthStart,
            to: end
        )) ?? []
    }

    private func setBudget(category: CategoryMO) {
        guard let services = appModel.services, let scope = appModel.activeScope ?? appModel.personalScope else { return }
        try? services.budgets.setBudget(
            category: category, scope: scope,
            monthKey: BudgetService.monthKey(for: monthStart, preference: AppPreferences.calendar),
            amountMinor: 0, currency: AppPreferences.baseCurrency
        )
        reload()
    }

    private func updateBudget(category: CategoryMO, amountText: String) {
        guard let services = appModel.services, let scope = appModel.activeScope ?? appModel.personalScope else { return }
        let minor = MoneyInput.parseMinorUnits(amountText, currency: AppPreferences.baseCurrency) ?? 0
        try? services.budgets.setBudget(
            category: category, scope: scope,
            monthKey: BudgetService.monthKey(for: monthStart, preference: AppPreferences.calendar),
            amountMinor: minor, currency: AppPreferences.baseCurrency
        )
        reload()
    }
}

/// Adds a category to the current month's budget list.
private struct BudgetPicker: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [CategoryMO]
    let onPick: (CategoryMO) -> Void

    @State private var selection: CategoryMO?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(String(localized: "Category"), selection: $selection) {
                    Text(String(localized: "Choose…")).tag(CategoryMO?.none)
                    ForEach(categories, id: \.objectID) { category in
                        Text(category.name).tag(CategoryMO?.some(category))
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Add")) {
                    if let selection {
                        onPick(selection)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding()
        }
    }
}

/// Edits a budget limit (empty or 0 removes the row).
private struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    let row: BudgetService.Row
    let onSave: (CategoryMO, String) -> Void

    @State private var amountText = ""
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(String(localized: "Category"), value: row.entry.category?.name ?? "—")
                AmountField(title: String(localized: "Monthly Limit"), currencyCode: row.entry.currencyCode, text: $amountText)
                Text(String(localized: "Enter 0 to remove this budget."))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    onSave(row.entry.category!, amountText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            var decimal = Decimal(row.entry.amountMinor)
            for _ in 0..<Currency.resolving(row.entry.currencyCode).minorUnitScale { decimal /= 10 }
            amountText = row.entry.amountMinor == 0 ? "" : "\(decimal)"
        }
    }
}
