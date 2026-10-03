import CoreData
import ProMeData
import ProMeDesignSystem
import ProMeDomain
import SwiftUI

/// Money-amount text field. Parses on save (never on every keystroke) so
/// partial input never produces silent zeros.
struct AmountField: View {
    let title: String
    let currencyCode: String
    @Binding var text: String

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.appBody.monospacedDigit())
                .frame(maxWidth: 220)
            Text(Currency.resolving(currencyCode).code)
                .foregroundStyle(.secondary)
        }
    }
}

/// Account picker with an inline "New Account…" action, so a missing
/// account never interrupts capturing a transaction.
struct AccountPicker: View {
    let title: String
    @Binding var selection: MoneyAccountMO?
    let accounts: [MoneyAccountMO]
    var onNewAccount: (() -> Void)? = nil

    var body: some View {
        Menu {
            Picker(title, selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )) {
                Text(String(localized: "Choose…")).tag(MoneyAccountMO?.none)
                ForEach(accounts, id: \.objectID) { account in
                    Label(account.name, systemImage: account.type.systemImage)
                        .tag(MoneyAccountMO?.some(account))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button {
                onNewAccount?()
            } label: {
                Label(String(localized: "New Account…"), systemImage: "plus.square.on.square")
            }
            .disabled(onNewAccount == nil)
        } label: {
            HStack {
                if let selection {
                    Label(selection.name, systemImage: selection.type.systemImage)
                } else {
                    Text(title).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }
}

/// Category picker with an inline "New Category…" action.
struct CategoryPicker: View {
    let title: String
    let kind: CategoryKind
    @Binding var selection: CategoryMO?
    let categories: [CategoryMO]
    var onNewCategory: (() -> Void)? = nil

    var body: some View {
        Menu {
            Picker(title, selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )) {
                Text(String(localized: "Choose…")).tag(CategoryMO?.none)
                ForEach(categories.filter { $0.kind == kind && $0.parent == nil }, id: \.objectID) { root in
                    Text(root.name).tag(CategoryMO?.some(root))
                    ForEach(sortedChildren(root), id: \.objectID) { child in
                        Text("  \(child.name)").tag(CategoryMO?.some(child))
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button {
                onNewCategory?()
            } label: {
                Label(String(localized: "New Category…"), systemImage: "plus.square.on.square")
            }
            .disabled(onNewCategory == nil)
        } label: {
            HStack {
                if let selection {
                    Text(selection.name)
                } else {
                    Text(title).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    private func sortedChildren(_ parent: CategoryMO) -> [CategoryMO] {
        parent.children.sorted { $0.name < $1.name }
    }
}

/// Full editor for income/expense transactions (new, edit, duplicate).
struct TransactionEditor: View {
    enum Mode {
        case new(TransactionKind)
        case edit(TransactionMO)
        case duplicate(TransactionMO)
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var account: MoneyAccountMO?
    @State private var category: CategoryMO?
    @State private var memo = ""
    @State private var notes = ""
    @State private var counterparty = ""
    @State private var reference = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var categories: [CategoryMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var inlineAccountSheet = false
    @State private var inlineCategorySheet = false

    private var isEditable: Bool {
        switch mode {
        case .edit(let transaction): return transaction.kind == .income || transaction.kind == .expense
        case .new: return true
        case .duplicate: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(String(localized: "Type"), selection: $kind) {
                    Text(String(localized: "Expense")).tag(TransactionKind.expense)
                    Text(String(localized: "Income")).tag(TransactionKind.income)
                }
                .disabled(mode.isEdit)
                .onChange(of: kind) { _ in
                    category = nil
                }

                AmountField(title: String(localized: "Amount"), currencyCode: account?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)

                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts, onNewAccount: { inlineAccountSheet = true })

                if kind == .expense {
                    CategoryPicker(title: String(localized: "Category"), kind: .expense, selection: $category, categories: categories, onNewCategory: { inlineCategorySheet = true })
                } else {
                    CategoryPicker(title: String(localized: "Category"), kind: .income, selection: $category, categories: categories, onNewCategory: { inlineCategorySheet = true })
                }

                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)

                TextField(String(localized: "Description"), text: $memo)
                TextField(String(localized: "Counterparty"), text: $counterparty)
                TextField(String(localized: "Reference"), text: $reference)
                TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(account == nil || category == nil)
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
        .sheet(isPresented: $inlineCategorySheet) {
            CategoryEditor(kind: kind == .expense ? .expense : .income, category: nil, onCreated: { created in
                if !categories.contains(where: { $0.objectID == created.objectID }) {
                    categories.append(created)
                }
                category = created
            })
            .frame(minWidth: 380, minHeight: 260)
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
        accounts = (try? services.accounts.allAccounts()) ?? []
        categories = (try? services.categories.allCategories()) ?? []

        switch mode {
        case .new(let initialKind):
            kind = initialKind
            // Prefill from the most recent transaction of the same kind.
            let recent = (try? services.transactions.fetch(
                TransactionQuery(kinds: [initialKind], sort: .date, ascending: false), limit: 1
            ))?.first
            account = recent?.account ?? accounts.first
            category = recent?.category
        case .edit(let transaction):
            kind = transaction.kind
            amountText = formatForEditing(transaction.amountMinor, code: transaction.currencyCode)
            date = transaction.postedAt
            account = transaction.account
            category = transaction.category
            memo = transaction.memo ?? ""
            notes = transaction.notes ?? ""
            counterparty = transaction.counterparty?.displayName ?? ""
            reference = transaction.referenceNo ?? ""
        case .duplicate(let transaction):
            kind = transaction.kind
            amountText = formatForEditing(transaction.amountMinor, code: transaction.currencyCode)
            date = transaction.postedAt
            account = transaction.account
            category = transaction.category
            memo = transaction.memo ?? ""
            notes = transaction.notes ?? ""
            counterparty = transaction.counterparty?.displayName ?? ""
            reference = transaction.referenceNo ?? ""
        }
    }

    private func formatForEditing(_ minor: Int64, code: String) -> String {
        let currency = Currency.resolving(code)
        var decimal = Decimal(minor)
        for _ in 0..<currency.minorUnitScale { decimal /= 10 }
        return "\(decimal)"
    }

    private func save() {
        guard let services = appModel.services else { return }
        guard let account else {
            errorMessage = String(localized: "Choose an account first.")
            return
        }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: account.currency) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        guard let category else {
            errorMessage = String(localized: "Choose a category first.")
            return
        }
        guard let scope = account.scope else {
            errorMessage = String(localized: "The account has no scope.")
            return
        }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCounterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch mode {
            case .new, .duplicate:
                if kind == .expense {
                    _ = try services.posting.postExpense(
                        scope: scope, account: account, category: category,
                        amountMinor: minor, date: date, memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                        counterpartyName: trimmedCounterparty.isEmpty ? nil : trimmedCounterparty,
                        referenceNo: reference.isEmpty ? nil : reference
                    )
                } else {
                    _ = try services.posting.postIncome(
                        scope: scope, account: account, category: category,
                        amountMinor: minor, date: date, memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                        counterpartyName: trimmedCounterparty.isEmpty ? nil : trimmedCounterparty,
                        referenceNo: reference.isEmpty ? nil : reference
                    )
                }
                dismiss()
            case .edit(let transaction):
                try services.posting.updateSimple(
                    transaction, account: account, category: category,
                    amountMinor: minor, date: date,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                    notes: notes.isEmpty ? nil : notes,
                    counterpartyName: trimmedCounterparty.isEmpty ? nil : trimmedCounterparty,
                    referenceNo: reference.isEmpty ? nil : reference
                )
                dismiss()
            }
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}

extension TransactionEditor.Mode {
    var isEdit: Bool {
        if case .edit = self { return true }
        return false
    }

    static func == (lhs: TransactionEditor.Mode, rhs: TransactionEditor.Mode) -> Bool {
        switch (lhs, rhs) {
        case (.new(let a), .new(let b)): return a == b
        case (.edit(let a), .edit(let b)): return a.objectID == b.objectID
        case (.duplicate(let a), .duplicate(let b)): return a.objectID == b.objectID
        default: return false
        }
    }
}

/// Minimal fast-capture sheet (⌘N): amount, account, category, memo.
/// Stays open so several transactions can be entered in a row.
struct QuickEntryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var account: MoneyAccountMO?
    @State private var category: CategoryMO?
    @State private var memo = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var categories: [CategoryMO] = []
    @State private var errorMessage: String?
    @State private var justSaved = false
    @State private var loaded = false
    @State private var inlineAccountSheet = false
    @State private var inlineCategorySheet = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(String(localized: "Type"), selection: $kind) {
                    Text(String(localized: "Expense")).tag(TransactionKind.expense)
                    Text(String(localized: "Income")).tag(TransactionKind.income)
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _ in category = preselectCategory() }

                AmountField(title: String(localized: "Amount"), currencyCode: account?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)
                    .onSubmit(save)

                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts, onNewAccount: { inlineAccountSheet = true })

                if kind == .expense {
                    CategoryPicker(title: String(localized: "Category"), kind: .expense, selection: $category, categories: categories, onNewCategory: { inlineCategorySheet = true })
                } else {
                    CategoryPicker(title: String(localized: "Category"), kind: .income, selection: $category, categories: categories, onNewCategory: { inlineCategorySheet = true })
                }

                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
                TextField(String(localized: "Description"), text: $memo)
                    .onSubmit(save)
            }
            .formStyle(.grouped)

            HStack {
                if justSaved {
                    Label(String(localized: "Saved"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ProMeColor.income)
                        .transition(.opacity)
                }
                Spacer()
                Button(String(localized: "Close"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save and Next"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(account == nil || category == nil)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear(perform: load)
        .task(id: memo) {
            // Smart categorization: pre-fill an empty category from past
            // transactions with a similar description (≥2 matches).
            guard memo.trimmingCharacters(in: .whitespaces).count >= 3, category == nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let kind: CategoryKind = self.kind == .expense ? .expense : .income
            if let suggestion = try? appModel.services?.categorization.suggestCategory(kind: kind, memo: memo) {
                if category == nil {
                    category = suggestion
                }
            }
        }
        .sheet(isPresented: $inlineAccountSheet) {
            AccountEditor(account: nil, onCreated: { created in
                if !accounts.contains(where: { $0.objectID == created.objectID }) {
                    accounts.append(created)
                }
                account = created
            })
            .frame(minWidth: 440, minHeight: 430)
        }
        .sheet(isPresented: $inlineCategorySheet) {
            CategoryEditor(kind: kind == .expense ? .expense : .income, category: nil, onCreated: { created in
                if !categories.contains(where: { $0.objectID == created.objectID }) {
                    categories.append(created)
                }
                category = created
            })
            .frame(minWidth: 380, minHeight: 260)
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
        accounts = (try? services.accounts.allAccounts()) ?? []
        categories = (try? services.categories.allCategories()) ?? []
        let recent = (try? services.transactions.fetch(
            TransactionQuery(kinds: [.expense], sort: .date, ascending: false), limit: 1
        ))?.first
        account = recent?.account ?? accounts.first
        category = recent?.category ?? categories.first { $0.kind == .expense && $0.parent != nil }
    }

    private func preselectCategory() -> CategoryMO? {
        categories.first { $0.kind == (kind == .expense ? .expense : .income) && $0.parent != nil }
    }

    private func save() {
        guard let services = appModel.services else { return }
        guard let account else {
            errorMessage = String(localized: "Choose an account first.")
            return
        }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: account.currency) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        guard let category else {
            errorMessage = String(localized: "Choose a category first.")
            return
        }
        guard let scope = account.scope else {
            errorMessage = String(localized: "The account has no scope.")
            return
        }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if kind == .expense {
                _ = try services.posting.postExpense(
                    scope: scope, account: account, category: category,
                    amountMinor: minor, date: date, memo: trimmedMemo.isEmpty ? nil : trimmedMemo
                )
            } else {
                _ = try services.posting.postIncome(
                    scope: scope, account: account, category: category,
                    amountMinor: minor, date: date, memo: trimmedMemo.isEmpty ? nil : trimmedMemo
                )
            }
            amountText = ""
            memo = ""
            date = .now
            withAnimation { justSaved = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation { justSaved = false }
            }
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
