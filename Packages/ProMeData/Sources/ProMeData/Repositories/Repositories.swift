import CoreData
import Foundation
import ProMeDomain

/// CRUD for financial scopes (Personal + businesses).
@MainActor
public final class ScopeRepository {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func allScopes() throws -> [FinancialScopeMO] {
        let request = FinancialScopeMO.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Creates the Personal scope if it does not exist yet.
    public func ensurePersonalScope() throws -> FinancialScopeMO {
        let request = FinancialScopeMO.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", ScopeKind.personal.rawValue)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let scope = FinancialScopeMO(context: context)
        scope.id = UUID()
        scope.name = "Personal"
        scope.kind = .personal
        scope.isActive = true
        scope.createdAt = .now
        try controller.saveViewContext()
        return scope
    }

    public func createBusiness(name: String, tradeName: String?, startDate: Date, baseCurrency: Currency) throws -> FinancialScopeMO {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.missingField("name") }
        let scope = FinancialScopeMO(context: context)
        scope.id = UUID()
        scope.name = trimmed
        scope.kind = .business
        scope.isActive = true
        scope.createdAt = .now
        let business = BusinessMO(context: context)
        business.id = UUID()
        business.legalName = trimmed
        business.tradeName = tradeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        business.startDate = startDate
        business.baseCurrencyCode = baseCurrency.code
        business.scope = scope
        try controller.saveViewContext()
        return scope
    }

    /// Scopes may only be deleted while completely empty.
    public func delete(_ scope: FinancialScopeMO) throws {
        guard scope.kind == .business else {
            throw ValidationError.invalidState("The Personal scope cannot be deleted.")
        }
        guard scope.accounts.isEmpty, scope.transactions.isEmpty, scope.recurringTransactions.isEmpty else {
            throw ValidationError.invalidState("This business still has accounts or transactions.")
        }
        context.delete(scope)
        try controller.saveViewContext()
    }
}

/// CRUD for money accounts; every account owns its asset ledger account.
@MainActor
public final class AccountRepository {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public struct Draft {
        public var name: String
        public var bankName: String?
        public var type: AccountType
        public var currency: Currency
        public var openingBalanceMinor: Int64
        public var openedAt: Date
        public var accountNumber: String?
        public var cardNumber: String?
        public var iban: String?
        public var notes: String?

        public init(
            name: String,
            bankName: String? = nil,
            type: AccountType = .current,
            currency: Currency = .irr,
            openingBalanceMinor: Int64 = 0,
            openedAt: Date = .now,
            accountNumber: String? = nil,
            cardNumber: String? = nil,
            iban: String? = nil,
            notes: String? = nil
        ) {
            self.name = name
            self.bankName = bankName
            self.type = type
            self.currency = currency
            self.openingBalanceMinor = openingBalanceMinor
            self.openedAt = openedAt
            self.accountNumber = accountNumber
            self.cardNumber = cardNumber
            self.iban = iban
            self.notes = notes
        }
    }

    public func allAccounts(includeArchived: Bool = false) throws -> [MoneyAccountMO] {
        let request = MoneyAccountMO.fetchRequest()
        if !includeArchived {
            request.predicate = NSPredicate(format: "statusRaw == %@", AccountStatus.active.rawValue)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    public func accounts(in scope: FinancialScopeMO?) throws -> [MoneyAccountMO] {
        guard let scope else { return try allAccounts() }
        let request = MoneyAccountMO.fetchRequest()
        request.predicate = NSPredicate(format: "scope == %@ AND statusRaw == %@", scope, AccountStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        return try context.fetch(request)
    }

    public func create(_ draft: Draft, in scope: FinancialScopeMO) throws -> MoneyAccountMO {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingField("name") }
        guard draft.openingBalanceMinor >= 0 else { throw ValidationError.invalidAmount("The opening balance cannot be negative.") }

        let account = MoneyAccountMO(context: context)
        account.id = UUID()
        account.name = name
        account.bankName = draft.bankName
        account.type = draft.type
        account.currencyCode = draft.currency.code
        account.openingBalanceMinor = draft.openingBalanceMinor
        account.openedAt = draft.openedAt
        account.accountNumber = draft.accountNumber
        account.cardNumber = draft.cardNumber
        account.iban = draft.iban
        account.notes = draft.notes
        account.status = .active
        account.position = nextPosition()
        account.createdAt = .now
        account.updatedAt = .now
        account.scope = scope

        account.ledgerAccount = try Self.ensureAssetLedger(for: account, in: context)

        // Opening balance is posted through the ledger (credit: equity) so
        // the ledger remains the single source of truth for balances.
        if draft.openingBalanceMinor > 0 {
            try Self.postOpeningBalance(for: account, in: context)
        }

        try controller.saveViewContext()
        return account
    }

    public func update(_ account: MoneyAccountMO, draft: Draft) throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingField("name") }
        account.name = name
        account.bankName = draft.bankName
        account.type = draft.type
        account.accountNumber = draft.accountNumber
        account.cardNumber = draft.cardNumber
        account.iban = draft.iban
        account.notes = draft.notes
        account.updatedAt = .now
        account.ledgerAccount?.name = name
        try controller.saveViewContext()
    }

    public func setArchived(_ account: MoneyAccountMO, archived: Bool) throws {
        account.status = archived ? .archived : .active
        account.updatedAt = .now
        try controller.saveViewContext()
    }

    /// Accounts with any transaction history are archived, never deleted.
    public func delete(_ account: MoneyAccountMO) throws {
        guard account.transactions.isEmpty, account.outgoingTransfers.isEmpty,
              account.incomingTransfers.isEmpty, account.recurringTransactions.isEmpty else {
            throw ValidationError.invalidState("This account has transactions and is archived instead of deleted.")
        }
        context.delete(account)
        try controller.saveViewContext()
    }

    // MARK: - Helpers

    private func nextPosition() -> Int32 {
        (try? context.count(for: MoneyAccountMO.fetchRequest())).map { Int32($0) } ?? 0
    }

    public static func ensureAssetLedger(for account: MoneyAccountMO, in context: NSManagedObjectContext) throws -> LedgerAccountMO {
        if let existing = account.ledgerAccount { return existing }
        let ledger = LedgerAccountMO(context: context)
        ledger.id = UUID()
        ledger.code = ChartOfAccounts.assetAccountCode(forAccountID: account.id)
        ledger.name = account.name
        ledger.type = .asset
        ledger.normalSide = .debit
        ledger.createdAt = .now
        return ledger
    }

    public static func postOpeningBalance(for account: MoneyAccountMO, in context: NSManagedObjectContext) throws {
        let equity = try ensureLedgerAccount(code: ChartOfAccounts.personalEquityCode, name: "Opening Balance", type: .equity, normalSide: .credit, in: context)
        let journal = JournalMO(context: context)
        journal.id = UUID()
        journal.kind = .adjustment
        journal.date = account.openedAt
        journal.createdAt = .now
        journal.memo = "Opening balance"

        let debit = LedgerLineMO(context: context)
        debit.id = UUID()
        debit.direction = .debit
        debit.amountMinor = account.openingBalanceMinor
        debit.currencyCode = account.currencyCode
        debit.journal = journal
        debit.ledgerAccount = account.ledgerAccount

        let credit = LedgerLineMO(context: context)
        credit.id = UUID()
        credit.direction = .credit
        credit.amountMinor = account.openingBalanceMinor
        credit.currencyCode = account.currencyCode
        credit.journal = journal
        credit.ledgerAccount = equity
    }

    public static func ensureLedgerAccount(
        code: String,
        name: String,
        type: LedgerAccountType,
        normalSide: LedgerDirection,
        in context: NSManagedObjectContext
    ) throws -> LedgerAccountMO {
        let request = LedgerAccountMO.fetchRequest()
        request.predicate = NSPredicate(format: "code == %@", code)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let ledger = LedgerAccountMO(context: context)
        ledger.id = UUID()
        ledger.code = code
        ledger.name = name
        ledger.type = type
        ledger.normalSide = normalSide
        ledger.createdAt = .now
        return ledger
    }
}

/// CRUD for categories with a delete guard that protects financial history.
@MainActor
public final class CategoryRepository {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func allCategories(kind: CategoryKind? = nil) throws -> [CategoryMO] {
        let request = CategoryMO.fetchRequest()
        if let kind {
            request.predicate = NSPredicate(format: "kindRaw == %@", kind.rawValue)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    public func create(name: String, kind: CategoryKind, parent: CategoryMO?) throws -> CategoryMO {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.missingField("name") }
        if let parent {
            guard parent.kind == kind else {
                throw ValidationError.invalidState("A subcategory must match its parent type.")
            }
            guard parent.parent == nil else {
                throw ValidationError.invalidState("Categories support two levels for now.")
            }
        }
        if try find(name: trimmed, kind: kind, parent: parent) != nil {
            throw ValidationError.duplicateName(trimmed)
        }

        let category = CategoryMO(context: context)
        category.id = UUID()
        category.name = trimmed
        category.kind = kind
        category.isSystem = false
        category.createdAt = .now
        category.parent = parent
        category.ledgerAccount = try AccountRepository.ensureLedgerAccount(
            code: kind == .income
                ? ChartOfAccounts.incomeCategoryCode(forCategoryID: category.id)
                : ChartOfAccounts.expenseCategoryCode(forCategoryID: category.id),
            name: trimmed,
            type: kind == .income ? .income : .expense,
            normalSide: kind == .income ? .credit : .debit,
            in: context
        )
        try controller.saveViewContext()
        return category
    }

    public func rename(_ category: CategoryMO, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.missingField("name") }
        if try find(name: trimmed, kind: category.kind, parent: category.parent).map({ $0.objectID != category.objectID }) == true {
            throw ValidationError.duplicateName(trimmed)
        }
        category.name = trimmed
        category.ledgerAccount?.name = trimmed
        try controller.saveViewContext()
    }

    /// Deleting is refused whenever history depends on the category.
    public func delete(_ category: CategoryMO) throws {
        guard category.transactions.isEmpty else {
            throw ValidationError.invalidState("This category has transactions and cannot be deleted.")
        }
        guard category.children.isEmpty else {
            throw ValidationError.invalidState("This category has subcategories.")
        }
        guard category.budgetEntries.isEmpty, category.recurringTransactions.isEmpty else {
            throw ValidationError.invalidState("This category is used by budgets or recurring transactions.")
        }
        context.delete(category)
        try controller.saveViewContext()
    }

    private func find(name: String, kind: CategoryKind, parent: CategoryMO?) throws -> CategoryMO? {
        let request = CategoryMO.fetchRequest()
        if let parent {
            request.predicate = NSPredicate(format: "name == %@ AND kindRaw == %@ AND parent == %@", name, kind.rawValue, parent)
        } else {
            request.predicate = NSPredicate(format: "name == %@ AND kindRaw == %@ AND parent == nil", name, kind.rawValue)
        }
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
