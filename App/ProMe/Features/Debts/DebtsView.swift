import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Receivables & payables per counterparty, with payment recording that
/// keeps the ledger in sync.
struct DebtsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var direction: DebtKind = .receivable
    @State private var rows: [DebtMO] = []
    @State private var showNew = false
    @State private var paying: DebtMO?
    @State private var confirmDelete: DebtMO?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Kind"), selection: $direction) {
                Text(String(localized: "Receivables")).tag(DebtKind.receivable)
                Text(String(localized: "Payables")).tag(DebtKind.payable)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if rows.isEmpty {
                EmptyStateView(
                    systemImage: direction == .receivable ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark",
                    title: direction == .receivable ? String(localized: "No Receivables") : String(localized: "No Payables"),
                    detail: String(localized: "Track what people owe you — or what you owe them — with full ledger entries.")
                )
            } else {
                List {
                    ForEach(rows, id: \.objectID) { debt in
                        DebtRowView(debt: debt)
                            .contextMenu {
                                if debt.status == .open {
                                    Button(String(localized: "Record Payment…")) { paying = debt }
                                }
                                Divider()
                                Button(String(localized: "Delete"), role: .destructive) { confirmDelete = debt }
                            }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Debts & Receivables"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Debt"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(direction)-\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            DebtEditor(direction: direction)
                .frame(minWidth: 420, minHeight: 340)
        }
        .sheet(item: $paying, onDismiss: { reload() }) { debt in
            DebtPaymentSheet(debt: debt)
                .frame(minWidth: 400, minHeight: 280)
        }
        .confirmationDialog(
            String(localized: "Delete this debt?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) { deleteDebt() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Its accounting entries are reversed as well."))
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
        rows = (try? services.debts.all(direction: direction, scope: appModel.activeScope)) ?? []
    }

    private func deleteDebt() {
        guard let services = appModel.services, let debt = confirmDelete else { return }
        do {
            try services.debts.delete(debt)
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

private struct DebtRowView: View {
    let debt: DebtMO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(debt.direction == .receivable ? ProMeColor.income : ProMeColor.expense)

            VStack(alignment: .leading, spacing: 2) {
                Text(debt.counterparty?.displayName ?? "—")
                    .font(.appBody.weight(.medium))
                HStack(spacing: 6) {
                    if let due = debt.dueDate {
                        Text(String(localized: "Due") + " " + Format.dateText(due))
                            .foregroundStyle(isOverdue ? ProMeColor.expense : .secondary)
                    }
                    if debt.status == .settled {
                        Text(String(localized: "Settled"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.appCaption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.amount(debt.remainingMinor, code: debt.currencyCode))
                    .font(.appCallout.monospacedDigit().weight(.semibold))
                Text(String(localized: "of \(Format.amount(debt.principalMinor, code: debt.currencyCode))"))
                    .font(.appCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var isOverdue: Bool {
        debt.status == .open && (debt.dueDate ?? .distantFuture) < .now
    }
}

struct DebtEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let direction: DebtKind

    @State private var counterparty = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var hasDue = false
    @State private var dueDate = Date().addingTimeInterval(30 * 86400)
    @State private var account: MoneyAccountMO?
    @State private var notes = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(String(localized: "Kind"), value: direction == .receivable ? String(localized: "Receivables") : String(localized: "Payables"))
                TextField(String(localized: "Counterparty"), text: $counterparty)
                AmountField(title: String(localized: "Amount"), currencyCode: account?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)
                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts, onNewAccount: { inlineAccountSheet = true })
                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
                Toggle(String(localized: "Has Due Date"), isOn: $hasDue)
                if hasDue {
                    DatePicker(String(localized: "Due"), selection: $dueDate, displayedComponents: .date)
                }
                TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                    .lineLimit(2...3)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(counterparty.trimmingCharacters(in: .whitespaces).isEmpty || account == nil)
            }
            .padding()
        }
        .onAppear(perform: load)
        .sheet(isPresented: $inlineAccountSheet) {
            AccountEditor(account: nil, onCreated: { created in
                if !accounts.contains(where: { $0.objectID == created.objectID }) {
                    accounts.append(created)
                }
                account = created
            })
            .frame(minWidth: 440, minHeight: 430)
        }
        .alert(String(localized: "Cannot Save"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @State private var inlineAccountSheet = false

    private func load() {
        guard !loaded, let services = appModel.services else { return }
        loaded = true
        accounts = (try? services.accounts.accounts(in: appModel.activeScope)) ?? []
        if accounts.isEmpty {
            accounts = (try? services.accounts.allAccounts()) ?? []
        }
        account = accounts.first
    }

    private func save() {
        guard let services = appModel.services, let account else { return }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: account.currency) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        guard let scope = appModel.activeScope ?? appModel.personalScope else {
            errorMessage = String(localized: "No scope available.")
            return
        }
        do {
            _ = try services.debts.create(
                DebtService.NewDebt(
                    direction: direction,
                    counterpartyName: counterparty,
                    principalMinor: minor,
                    date: date,
                    dueDate: hasDue ? dueDate : nil,
                    account: account,
                    notes: notes.isEmpty ? nil : notes
                ),
                in: scope
            )
            appModel.bumpData()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}

private struct DebtPaymentSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let debt: DebtMO

    @State private var amountText = ""
    @State private var date = Date()
    @State private var account: MoneyAccountMO?
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(String(localized: "Counterparty"), value: debt.counterparty?.displayName ?? "—")
                LabeledContent(String(localized: "Remaining"), value: Format.amount(debt.remainingMinor, code: debt.currencyCode))
                AmountField(title: String(localized: "Amount"), currencyCode: debt.currencyCode, text: $amountText)
                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts)
                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Record Payment"), action: save)
                    .keyboardShortcut(.defaultAction)
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
        accounts = (try? services.accounts.accounts(in: debt.scope)) ?? []
        account = accounts.first
        var decimal = Decimal(debt.remainingMinor)
        for _ in 0..<Currency.resolving(debt.currencyCode).minorUnitScale { decimal /= 10 }
        amountText = "\(decimal)"
    }

    private func save() {
        guard let services = appModel.services, let account else { return }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: Currency.resolving(debt.currencyCode)) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        do {
            _ = try services.debts.recordPayment(debt, account: account, amountMinor: minor, date: date)
            appModel.bumpData()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
