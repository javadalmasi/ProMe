import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Recurring transactions: rent, insurance premiums, salaries… with
/// catch-up posting and manual "post now".
struct RecurringView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [RecurringTransactionMO] = []
    @State private var editing: RecurringTransactionMO?
    @State private var showNew = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.clockwise.circle",
                    title: String(localized: "No Recurring Transactions"),
                    detail: String(localized: "Automate rent, premiums and salaries so nothing is forgotten.")
                )
            } else {
                List {
                    ForEach(rows, id: \.objectID) { recurring in
                        RecurringRowView(recurring: recurring) {
                            postNow(recurring)
                        }
                        .contextMenu {
                            Button(String(localized: "Post Now")) { postNow(recurring) }
                            Button(String(localized: "Edit")) { editing = recurring }
                            Divider()
                            Button(String(localized: "Stop"), role: .destructive) { stop(recurring) }
                        }
                    }
                }
                #if os(macOS)
                .appListStyle()
#else
                .listStyle(.inset)
#endif
            }
        }
        .navigationTitle(String(localized: "Recurring"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Recurring"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            RecurringEditor(recurring: nil)
                .frame(minWidth: 440, minHeight: 430)
        }
        .sheet(item: $editing, onDismiss: { reload() }) { recurring in
            RecurringEditor(recurring: recurring)
                .frame(minWidth: 440, minHeight: 430)
        }
        .alert(String(localized: "Something went wrong"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        rows = (try? services.recurring.all()) ?? []
    }

    private func postNow(_ recurring: RecurringTransactionMO) {
        do {
            try appModel.services?.recurring.postDue(of: recurring, asOf: .now)
            NotificationsService.refreshReminders(appModel: appModel)
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }

    private func stop(_ recurring: RecurringTransactionMO) {
        try? appModel.services?.recurring.cancel(recurring)
        reload()
    }
}

private struct RecurringRowView: View {
    let recurring: RecurringTransactionMO
    let onPostNow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recurring.kind.systemImage)
                .foregroundStyle(recurring.kind == .income ? ProMeColor.income : ProMeColor.expense)

            VStack(alignment: .leading, spacing: 2) {
                Text(recurring.memo ?? recurring.category?.name ?? recurring.kind.displayName)
                    .font(.appBody.weight(.medium))
                HStack(spacing: 6) {
                    Text(frequencyText)
                    if let account = recurring.account {
                        Text("·")
                        Text(account.name)
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.amount(recurring.amountMinor, code: recurring.currencyCode))
                    .font(.appCallout.monospacedDigit().weight(.semibold))
                HStack(spacing: 4) {
                    Text(String(localized: "Next") + " " + Format.dateText(recurring.nextDueAt))
                        .font(.appCaption)
                        .foregroundStyle(recurring.nextDueAt <= .now ? ProMeColor.expense : .secondary)
                    if recurring.nextDueAt <= .now {
                        Button(String(localized: "Post Now"), action: onPostNow)
                            .font(.appCaption)
                            .buttonStyle(.appLink)
                    }
                }
            }
            .frame(width: 230, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var frequencyText: String {
        let rule = recurring.rule
        if rule.interval == 1 {
            return rule.frequency.displayName
        }
        return String(localized: "Every \(rule.interval)") + " " + rule.frequency.displayName
    }
}

struct RecurringEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let recurring: RecurringTransactionMO?

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var account: MoneyAccountMO?
    @State private var category: CategoryMO?
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date().addingTimeInterval(365 * 86400)
    @State private var autoPost = true
    @State private var memo = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var categories: [CategoryMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(String(localized: "Type"), selection: $kind) {
                    Text(String(localized: "Expense")).tag(TransactionKind.expense)
                    Text(String(localized: "Income")).tag(TransactionKind.income)
                }
                .pickerStyle(.segmented)
                .disabled(recurring != nil)
                .onChange(of: kind) { _ in category = nil }

                AmountField(title: String(localized: "Amount"), currencyCode: account?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)

                Picker(String(localized: "Account"), selection: $account) {
                    Text(String(localized: "Choose…")).tag(MoneyAccountMO?.none)
                    ForEach(accounts, id: \.objectID) { item in
                        Label(item.name, systemImage: item.type.systemImage)
                            .tag(MoneyAccountMO?.some(item))
                    }
                }

                CategoryPicker(
                    title: String(localized: "Category"),
                    kind: kind == .expense ? .expense : .income,
                    selection: $category,
                    categories: categories
                )

                Picker(String(localized: "Frequency"), selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Stepper(String(localized: "Every \(interval)"), value: $interval, in: 1...36)

                DatePicker(String(localized: "Start Date"), selection: $startDate, displayedComponents: .date)
                Toggle(String(localized: "Has End Date"), isOn: $hasEnd)
                if hasEnd {
                    DatePicker(String(localized: "End Date"), selection: $endDate, displayedComponents: .date)
                }
                Toggle(String(localized: "Post Automatically"), isOn: $autoPost)
                TextField(String(localized: "Description"), text: $memo)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(account == nil || category == nil)
            }
            .padding()
        }
        .onAppear(perform: load)
        .alert(String(localized: "Cannot Save"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() {
        guard !loaded, let services = appModel.services else { return }
        loaded = true
        accounts = (try? services.accounts.allAccounts()) ?? []
        categories = (try? services.categories.allCategories()) ?? []
        if let recurring {
            kind = recurring.kind
            var decimal = Decimal(recurring.amountMinor)
            for _ in 0..<Currency.resolving(recurring.currencyCode).minorUnitScale { decimal /= 10 }
            amountText = "\(decimal)"
            account = recurring.account
            category = recurring.category
            frequency = recurring.frequency
            interval = Int(recurring.interval)
            startDate = recurring.startDate
            hasEnd = recurring.endDate != nil
            endDate = recurring.endDate ?? startDate.addingTimeInterval(365 * 86400)
            autoPost = recurring.autoPost
            memo = recurring.memo ?? ""
        } else {
            account = accounts.first
            category = categories.first { $0.kind == .expense && $0.parent != nil }
        }
    }

    private func save() {
        guard let services = appModel.services else { return }
        guard let account else { return }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: account.currency) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        guard let category else {
            errorMessage = String(localized: "Choose a category first.")
            return
        }
        guard let scope = appModel.activeScope ?? account.scope ?? appModel.personalScope else {
            errorMessage = String(localized: "No scope available.")
            return
        }
        let draft = RecurringService.Draft(
            kind: kind,
            amountMinor: minor,
            account: account,
            category: category,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            endDate: hasEnd ? endDate : nil,
            autoPost: autoPost,
            memo: memo.isEmpty ? nil : memo
        )
        do {
            if let recurring {
                try services.recurring.update(recurring, draft: draft)
            } else {
                _ = try services.recurring.create(draft, in: scope)
            }
            NotificationsService.refreshReminders(appModel: appModel)
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
