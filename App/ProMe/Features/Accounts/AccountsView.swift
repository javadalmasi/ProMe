import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Account cards with live ledger balances plus a detail inspector
/// (month activity, recent transactions, edit/archive/delete).
struct AccountsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var accounts: [MoneyAccountMO] = []
    @State private var balances: [UUID: Int64] = [:]
    @State private var selected: MoneyAccountMO?
    @State private var editing: MoneyAccountMO?
    @State private var reconciling: MoneyAccountMO?
    @State private var showNew = false
    @State private var confirmDelete: MoneyAccountMO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if accounts.isEmpty {
                EmptyStateView(
                    systemImage: "banknote",
                    title: String(localized: "No Accounts"),
                    detail: String(localized: "Add your first bank account, card or cash wallet.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                        ForEach(accounts, id: \.objectID) { account in
                            AccountCard(account: account, balance: balances[account.id] ?? 0)
                                .onTapGesture { selected = account }
                                .contextMenu {
                                    Button(String(localized: "Edit")) { editing = account }
                                    Button(String(localized: "Reconcile…")) { reconciling = account }
                                    Button(account.status == .archived ? String(localized: "Unarchive") : String(localized: "Archive")) {
                                        toggleArchive(account)
                                    }
                                    Divider()
                                    Button(String(localized: "Delete"), role: .destructive) { confirmDelete = account }
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(String(localized: "Accounts"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNew = true
                } label: {
                    Label(String(localized: "New Account"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .refreshable { reload() }
        .onAppear { reload() }
        .inspector(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let selected {
                AccountDetailView(account: selected) {
                    editing = selected
                } onReconcile: {
                    reconciling = selected
                } onArchive: {
                    toggleArchive(selected)
                } onDelete: {
                    confirmDelete = selected
                }
            }
        }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            AccountEditor(account: nil)
                .frame(minWidth: 440, minHeight: 430)
        }
        .sheet(item: $editing, onDismiss: { reload() }) { account in
            AccountEditor(account: account)
                .frame(minWidth: 440, minHeight: 430)
        }
        .sheet(item: $reconciling, onDismiss: { reload() }) { account in
            ReconcileSheet(account: account)
                .frame(minWidth: 560, minHeight: 480)
        }
        .confirmationDialog(
            String(localized: "Delete this account?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                deleteAccount()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Accounts with history are archived instead."))
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
        accounts = (try? services.accounts.accounts(in: appModel.activeScope)) ?? []
        balances = (try? services.aggregates.accountBalances(accounts)) ?? [:]
    }

    private func toggleArchive(_ account: MoneyAccountMO) {
        try? appModel.services?.accounts.setArchived(account, archived: account.status != .archived)
        selected = nil
        reload()
    }

    private func deleteAccount() {
        guard let services = appModel.services, let account = confirmDelete else { return }
        do {
            try services.accounts.delete(account)
            selected = nil
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

private struct AccountCard: View {
    let account: MoneyAccountMO
    let balance: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: account.type.systemImage)
                    .foregroundStyle(ProMeColor.transfer)
                Text(account.name)
                    .font(.appHeadline)
                    .lineLimit(1)
                Spacer()
                if account.status == .archived {
                    Text(String(localized: "Archived"))
                        .font(.appCaption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
            }
            if let bank = account.bankName, !bank.isEmpty {
                HStack(spacing: 4) {
                    if let iranianBank = IranianBank.named(bank) {
                        BankLogo(iranianBank, size: 14)
                    }
                    Text(bank).font(.appCaption).foregroundStyle(.secondary)
                }
            }
            Text(Format.amount(balance, code: account.currencyCode))
                .font(.appTitle3.monospacedDigit().weight(.semibold))
                .foregroundStyle(balance < 0 ? ProMeColor.expense : Color.primary)
            Text(account.type.displayName)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .padding(ProMeSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ProMeSpacing.cardCorner).fill(.background.secondary))
        .contentShape(Rectangle())
    }
}

private struct AccountDetailView: View {
    @Environment(AppModel.self) private var appModel
    let account: MoneyAccountMO
    let onEdit: () -> Void
    let onReconcile: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var balance: Int64 = 0
    @State private var monthIn: Int64 = 0
    @State private var monthOut: Int64 = 0
    @State private var recent: [TransactionMO] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: account.type.systemImage).font(.appTitle2)
                    VStack(alignment: .leading) {
                        Text(account.name).font(.appTitle3.weight(.semibold))
                        Text(account.type.displayName).font(.appCaption).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        row(String(localized: "Balance"), Format.amount(balance, code: account.currencyCode))
                        row(String(localized: "This Month In"), "+" + Format.amount(monthIn, code: account.currencyCode))
                        row(String(localized: "This Month Out"), "−" + Format.amount(monthOut, code: account.currencyCode))
                        if let bank = account.bankName { row(String(localized: "Bank"), bank) }
                        if let number = account.accountNumber { row(String(localized: "Account Number"), number) }
                        if let card = account.cardNumber { row(String(localized: "Card Number"), card) }
                        if let iban = account.iban { row(String(localized: "IBAN"), iban) }
                        row(String(localized: "Opened"), Format.dateText(account.openedAt))
                    }
                }

                HStack {
                    Button(String(localized: "Edit"), action: onEdit)
                    Button(String(localized: "Reconcile…"), action: onReconcile)
                    Button(account.status == .archived ? String(localized: "Unarchive") : String(localized: "Archive"), action: onArchive)
                    Spacer()
                    Button(String(localized: "Delete"), role: .destructive, action: onDelete)
                }

                if !recent.isEmpty {
                    Text(String(localized: "Recent Transactions")).font(.appHeadline)
                    ForEach(recent, id: \.objectID) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
            .padding(20)
        }
        .inspectorColumnWidth(min: 280, ideal: 340)
        .task { load() }
        .onAppear { load() }
    }

    private func load() {
        guard let services = appModel.services else { return }
        balance = (try? services.aggregates.accountBalance(account)) ?? 0

        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        let month = resolver.monthContaining(.now)
        let income = (try? services.aggregates.sum(kind: .income, scope: account.scope, from: month.start, to: month.end)) ?? []
        let expense = (try? services.aggregates.sum(kind: .expense, scope: account.scope, from: month.start, to: month.end)) ?? []
        // Per-account in/out needs the account clause; approximate with the
        // account's own transactions for the month.
        let accountQuery = TransactionQuery(accountID: account.id, startDate: month.start, endDate: month.end)
        let rows = (try? services.transactions.fetch(accountQuery)) ?? []
        monthIn = rows.filter { $0.kind == .income || ($0.kind.isTransferLike && $0.toAccount?.objectID == account.objectID) }
            .reduce(0) { $0 + $1.amountMinor }
        monthOut = rows.filter { $0.kind == .expense || ($0.kind.isTransferLike && $0.fromAccount?.objectID == account.objectID) }
            .reduce(0) { $0 + $1.amountMinor }
        _ = income
        _ = expense

        let recentQuery = TransactionQuery(accountID: account.id, sort: .date, ascending: false)
        recent = Array((try? services.transactions.fetch(recentQuery, limit: 10)) ?? [])
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.appCallout)
    }
}

/// Create / edit form for accounts. `onCreated` lets pickers grab the
/// fresh account for inline selection.
struct AccountEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let account: MoneyAccountMO?
    var onCreated: ((MoneyAccountMO) -> Void)? = nil

    @State private var name = ""
    @State private var bankName = ""
    @State private var type: AccountType = .current
    @State private var currencyCode = "IRR"
    @State private var openingText = ""
    @State private var openedAt = Date()
    @State private var accountNumber = ""
    @State private var cardNumber = ""
    @State private var iban = ""
    @State private var notes = ""
    @State private var selectedBankID = ""
    @State private var shebaState = false
    @State private var errorMessage: String?
    @State private var loaded = false

    /// Auto-selects a bank from the card BIN.
    private func detectBank(from value: String) {
        guard let bank = IranianBank.matching(cardNumber: value) else { return }
        if selectedBankID.isEmpty || selectedBankID == bank.id {
            selectedBankID = bank.id
        }
    }

    private let knownCurrencies = ["IRT", "IRR", "USD", "EUR", "GBP", "AED", "TRY"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(String(localized: "Account Name"), text: $name)

                Picker(String(localized: "Bank"), selection: $selectedBankID) {
                    Text(String(localized: "No Bank (Cash/Wallet)")).tag("")
                    ForEach(IranianBank.all) { bank in
                        Label(bank.name, systemImage: "banknote").tag(bank.id)
                    }
                    Text(String(localized: "Other")).tag("other")
                }
                if selectedBankID == "other" {
                    TextField(String(localized: "Bank Name"), text: $bankName)
                }

                Picker(String(localized: "Type"), selection: $type) {
                    ForEach(AccountType.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker(String(localized: "Currency"), selection: $currencyCode) {
                    ForEach(knownCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .disabled(account != nil)
                if account == nil {
                    AmountField(title: String(localized: "Opening Balance"), currencyCode: currencyCode, text: $openingText)
                }
                DatePicker(String(localized: "Opened At"), selection: $openedAt, displayedComponents: .date)

                TextField(String(localized: "Account Number"), text: $accountNumber)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(String(localized: "Card Number"), text: $cardNumber)
                        .onChange(of: cardNumber) { _, newValue in
                            detectBank(from: newValue)
                        }
                    if !CardValidator.digits(in: cardNumber).isEmpty {
                        HStack(spacing: 6) {
                            if let bank = IranianBank.matching(cardNumber: cardNumber) {
                                BankLogo(bank, size: 18)
                                Text(bank.name).font(.appCaption)
                            }
                            Spacer()
                            if CardValidator.luhnValid(cardNumber) {
                                Label(String(localized: "Valid"), systemImage: "checkmark.circle.fill")
                                    .font(.appCaption2)
                                    .foregroundStyle(ProMeColor.income)
                            } else if CardValidator.digits(in: cardNumber).count >= 12 {
                                Label(String(localized: "Invalid checksum"), systemImage: "xmark.circle")
                                    .font(.appCaption2)
                                    .foregroundStyle(ProMeColor.expense)
                            }
                        }
                        Text(CardValidator.formattedCardNumber(cardNumber))
                            .font(.appCaption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField(String(localized: "IBAN (Sheba)"), text: $iban)
                        .onChange(of: iban) { _, newValue in
                            shebaState = ShebaValidator.isValid(newValue)
                            if let code = ShebaValidator.bankCode(of: newValue),
                               let bank = IranianBank.matching(shebaCode: code), selectedBankID.isEmpty {
                                selectedBankID = bank.id
                            }
                        }
                    if iban.count > 4 {
                        Label(
                            shebaState ? String(localized: "Valid Sheba") : String(localized: "Invalid Sheba"),
                            systemImage: shebaState ? "checkmark.circle.fill" : "xmark.circle"
                        )
                        .font(.appCaption2)
                        .foregroundStyle(shebaState ? ProMeColor.income : ProMeColor.expense)
                    }
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        guard !loaded else { return }
        loaded = true
        guard let account else { return }
        name = account.name
        bankName = account.bankName ?? ""
        selectedBankID = account.bankName.flatMap { IranianBank.named($0)?.id } ?? (account.bankName == nil ? "" : "other")
        type = account.type
        currencyCode = account.currencyCode
        openedAt = account.openedAt
        accountNumber = account.accountNumber ?? ""
        cardNumber = account.cardNumber ?? ""
        iban = account.iban ?? ""
        notes = account.notes ?? ""
    }

    private func save() {
        guard let services = appModel.services else { return }
        let resolvedBankName: String?
        if selectedBankID.isEmpty {
            resolvedBankName = nil
        } else if let bank = IranianBank.all.first(where: { $0.id == selectedBankID }) {
            resolvedBankName = bank.name
        } else {
            resolvedBankName = bankName.isEmpty ? nil : bankName
        }
        let opening = MoneyInput.parseMinorUnits(openingText, currency: .resolving(currencyCode)) ?? 0
        let draft = AccountRepository.Draft(
            name: name,
            bankName: resolvedBankName,
            type: type,
            currency: .resolving(currencyCode),
            openingBalanceMinor: opening,
            openedAt: openedAt,
            accountNumber: accountNumber.isEmpty ? nil : accountNumber,
            cardNumber: cardNumber.isEmpty ? nil : cardNumber,
            iban: iban.isEmpty ? nil : iban,
            notes: notes.isEmpty ? nil : notes
        )
        do {
            if let account {
                try services.accounts.update(account, draft: draft)
            } else {
                guard let scope = appModel.activeScope ?? appModel.personalScope else {
                    errorMessage = String(localized: "No scope available.")
                    return
                }
                let created = try services.accounts.create(draft, in: scope)
                onCreated?(created)
            }
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}


/// Compare the app balance at a date against the real bank statement,
/// mark matched transactions, and keep the reconciliation history.
struct ReconcileSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let account: MoneyAccountMO

    @State private var bankText = ""
    @State private var asOf = Date()
    @State private var appBalance: Int64 = 0
    @State private var rows: [TransactionMO] = []
    @State private var marked: Set<NSManagedObjectID> = []
    @State private var lastReconciled: Date?
    @State private var errorMessage: String?
    @State private var loaded = false

    private var bankMinor: Int64? {
        MoneyInput.parseMinorUnits(bankText, currency: account.currency)
    }

    private var difference: Int64? {
        bankMinor.map { $0 - appBalance }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let lastReconciled {
                    LabeledContent(String(localized: "Last Reconciled"), value: Format.dateText(lastReconciled))
                }
                LabeledContent(String(localized: "App Balance"), value: Format.amount(appBalance, code: account.currencyCode))
                AmountField(title: String(localized: "Bank Statement Balance"), currencyCode: account.currencyCode, text: $bankText)
                DatePicker(String(localized: "As Of"), selection: $asOf, displayedComponents: .date)
                if let difference {
                    LabeledContent(String(localized: "Difference"), value: Format.amount(difference, code: account.currencyCode))
                        .foregroundStyle(difference == 0 ? ProMeColor.income : ProMeColor.expense)
                }
            }
            .formStyle(.grouped)

            Text(String(localized: "Unreconciled Transactions"))
                .font(.appHeadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            List {
                ForEach(rows, id: \.objectID) { transaction in
                    HStack {
                        Image(systemName: marked.contains(transaction.objectID) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(marked.contains(transaction.objectID) ? ProMeColor.income : .secondary)
                            .onTapGesture { toggle(transaction) }
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
            .appListStyle()
            .frame(minHeight: 180)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Reconcile"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(bankMinor == nil)
            }
            .padding()
        }
        .onAppear(perform: load)
        .onChange(of: asOf) { reloadBalances() }
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
        lastReconciled = services.reconciliation.latest(account: account)?.asOfDate
        reloadBalances()
    }

    private func reloadBalances() {
        guard let services = appModel.services else { return }
        let exclusive = Calendar.current.startOfDay(for: asOf).addingTimeInterval(86_400)
        appBalance = (try? services.reconciliation.appBalance(account: account, before: exclusive)) ?? 0
        rows = (try? services.reconciliation.unreconciled(account: account, before: exclusive)) ?? []
        marked = []
    }

    private func toggle(_ transaction: TransactionMO) {
        if marked.contains(transaction.objectID) {
            marked.remove(transaction.objectID)
        } else {
            marked.insert(transaction.objectID)
        }
    }

    private func save() {
        guard let services = appModel.services else { return }
        guard let bank = bankMinor else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        let chosen = rows.filter { marked.contains($0.objectID) }
        do {
            _ = try services.reconciliation.reconcile(
                account: account, asOf: asOf, bankBalanceMinor: bank, marking: chosen
            )
            appModel.bumpData()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
