import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Loans with their installment schedule; paying an installment splits the
/// money into principal (liability reduction) and interest (expense).
struct LoansView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [LoanMO] = []
    @State private var remaining: [UUID: Int64] = [:]
    @State private var selected: LoanMO?
    @State private var showNew = false
    @State private var confirmDelete: LoanMO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "bank.building",
                    title: String(localized: "No Loans"),
                    detail: String(localized: "Record a loan and its installment schedule is generated automatically.")
                )
            } else {
                List(selection: $selected) {
                    ForEach(rows, id: \.objectID) { loan in
                        LoanRowView(loan: loan, remaining: remaining[loan.id] ?? 0)
                            .tag(loan)
                            .contextMenu {
                                Button(String(localized: "Delete"), role: .destructive) { confirmDelete = loan }
                            }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Loans"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Loan"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .inspector(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let selected {
                LoanDetailView(loan: selected) {
                    reload()
                }
            }
        }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            LoanEditor()
                .frame(minWidth: 440, minHeight: 430)
        }
        .confirmationDialog(
            String(localized: "Delete this loan?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) { deleteLoan() }
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
        rows = (try? services.loans.all(scope: appModel.activeScope)) ?? []
        var balances: [UUID: Int64] = [:]
        for loan in rows {
            balances[loan.id] = (try? services.loans.remainingPrincipal(loan)) ?? 0
        }
        remaining = balances
    }

    private func deleteLoan() {
        guard let services = appModel.services, let loan = confirmDelete else { return }
        do {
            try services.loans.delete(loan)
            selected = nil
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

private struct LoanRowView: View {
    let loan: LoanMO
    let remaining: Int64

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bank.building")
                .foregroundStyle(ProMeColor.transfer)

            VStack(alignment: .leading, spacing: 2) {
                Text(loan.lenderName).font(.appBody.weight(.medium))
                Text(subtitle).font(.appCaption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.amount(remaining, code: loan.currencyCode))
                    .font(.appCallout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(remaining > 0 ? Color.primary : ProMeColor.income)
                Text(String(localized: "of \(Format.amount(loan.principalMinor, code: loan.currencyCode))"))
                    .font(.appCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let total = loan.termMonths
        let paid = loan.paidInstallmentCount
        if loan.status == .settled {
            return String(localized: "Settled")
        }
        if let next = loan.sortedInstallments.first(where: { $0.status == .pending }) {
            let overdue = next.isOverdue ? " · " + String(localized: "Overdue") : ""
            return String(localized: "\(paid) of \(Int(total)) paid") + " · " + Format.dateText(next.dueDate) + overdue
        }
        return String(localized: "\(paid) of \(Int(total)) paid")
    }
}

/// Inspector: loan facts plus the full installment table with Pay actions.
private struct LoanDetailView: View {
    @Environment(AppModel.self) private var appModel
    let loan: LoanMO
    let onDataChanged: () -> Void

    @State private var remaining: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(String(localized: "Lender"), value: loan.lenderName)
                LabeledContent(String(localized: "Principal"), value: Format.amount(loan.principalMinor, code: loan.currencyCode))
                LabeledContent(String(localized: "Remaining"), value: Format.amount(remaining, code: loan.currencyCode))
                LabeledContent(String(localized: "Annual Rate"), value: "\(loan.ratePercent)%")
                LabeledContent(String(localized: "Term"), value: String(localized: "\(Int(loan.termMonths)) months"))
                LabeledContent(String(localized: "Started"), value: Format.dateText(loan.startDate))
                if let memo = loan.memo, !memo.isEmpty {
                    LabeledContent(String(localized: "Notes"), value: memo)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 240)

            Text(String(localized: "Installments"))
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            List {
                ForEach(loan.sortedInstallments, id: \.objectID) { installment in
                    installmentRow(installment)
                }
            }
            .appListStyle()
        }
        .inspectorColumnWidth(min: 320, ideal: 380)
        .task { remaining = (try? appModel.services?.loans.remainingPrincipal(loan)) ?? 0 }
        .onAppear { remaining = (try? appModel.services?.loans.remainingPrincipal(loan)) ?? 0 }
        .alert(String(localized: "Something went wrong"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func installmentRow(_ installment: LoanInstallmentMO) -> some View {
        HStack(spacing: 10) {
            Text("#\(Int(installment.index))")
                .font(.appCallout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Text(Format.dateText(installment.dueDate))
                .font(.appCallout.monospacedDigit())
                .foregroundStyle(installment.isOverdue ? ProMeColor.expense : .secondary)
                .frame(width: 100, alignment: .leading)
            Text(Format.amount(installment.totalMinor, code: loan.currencyCode))
                .font(.appCallout.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
            if installment.status == .paid {
                Label(String(localized: "Paid"), systemImage: "checkmark.circle.fill")
                    .font(.appCaption)
                    .foregroundStyle(ProMeColor.income)
            } else {
                Button(String(localized: "Pay")) { pay(installment) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func pay(_ installment: LoanInstallmentMO) {
        do {
            try appModel.services?.loans.pay(installment)
            remaining = (try? appModel.services?.loans.remainingPrincipal(loan)) ?? 0
            onDataChanged()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}

struct LoanEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var lenderName = ""
    @State private var amountText = ""
    @State private var rateText = "0"
    @State private var termMonths = 12
    @State private var startDate = Date()
    @State private var dueDay = 1
    @State private var account: MoneyAccountMO?
    @State private var memo = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var inlineAccountSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(String(localized: "Lender"), text: $lenderName)
                AmountField(title: String(localized: "Principal"), currencyCode: account?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)
                AmountField(title: String(localized: "Annual Rate %"), currencyCode: "%", text: $rateText)
                Stepper(String(localized: "Term") + ": \(termMonths)", value: $termMonths, in: 1...360)
                DatePicker(String(localized: "Start Date"), selection: $startDate, displayedComponents: .date)
                Stepper(String(localized: "Due Day") + ": \(dueDay)", value: $dueDay, in: 1...31)
                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts, onNewAccount: { inlineAccountSheet = true })
                TextField(String(localized: "Notes"), text: $memo)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(lenderName.trimmingCharacters(in: .whitespaces).isEmpty || account == nil)
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
        let rate = MoneyInput.parseDecimal(rateText) ?? 0
        guard let scope = appModel.activeScope ?? appModel.personalScope else {
            errorMessage = String(localized: "No scope available.")
            return
        }
        do {
            _ = try services.loans.create(
                LoanService.NewLoan(
                    lenderName: lenderName,
                    principalMinor: minor,
                    annualRatePercent: rate,
                    termMonths: termMonths,
                    startDate: startDate,
                    dueDay: dueDay,
                    account: account,
                    memo: memo.isEmpty ? nil : memo
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
