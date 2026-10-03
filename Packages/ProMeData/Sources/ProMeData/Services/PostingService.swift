import CoreData
import Foundation
import ProMeDomain

/// The only writer of financial events. Every mutation builds a balanced
/// journal through the Domain's JournalBuilder and persists transaction +
/// journal + ledger lines atomically.
@MainActor
public final class PostingService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    // MARK: - Post

    public func postExpense(
        scope: FinancialScopeMO,
        account: MoneyAccountMO,
        category: CategoryMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String? = nil,
        counterpartyName: String? = nil,
        referenceNo: String? = nil
    ) throws -> TransactionMO {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard category.kind == .expense else { throw ValidationError.invalidState("An expense needs an expense category.") }
        try ensureActive(account)
        let categoryLedger = try ledger(for: category)
        let accountLedger = try ledger(for: account)
        let journal = try JournalBuilder.build(kind: .expense, date: date, memo: memo, lines: [
            PostingLine(ledgerAccountCode: categoryLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: account.currency)),
            PostingLine(ledgerAccountCode: accountLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: account.currency)),
        ])
        return try persist(
            kind: .expense, journalKind: .expense, journal: journal, scope: scope,
            account: account, category: category, fromAccount: nil, toAccount: nil,
            memo: memo, notes: notes, counterpartyName: counterpartyName, referenceNo: referenceNo
        )
    }

    public func postIncome(
        scope: FinancialScopeMO,
        account: MoneyAccountMO,
        category: CategoryMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String? = nil,
        counterpartyName: String? = nil,
        referenceNo: String? = nil
    ) throws -> TransactionMO {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard category.kind == .income else { throw ValidationError.invalidState("An income needs an income category.") }
        try ensureActive(account)
        let categoryLedger = try ledger(for: category)
        let accountLedger = try ledger(for: account)
        let journal = try JournalBuilder.build(kind: .income, date: date, memo: memo, lines: [
            PostingLine(ledgerAccountCode: accountLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: account.currency)),
            PostingLine(ledgerAccountCode: categoryLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: account.currency)),
        ])
        return try persist(
            kind: .income, journalKind: .income, journal: journal, scope: scope,
            account: account, category: category, fromAccount: nil, toAccount: nil,
            memo: memo, notes: notes, counterpartyName: counterpartyName, referenceNo: referenceNo
        )
    }

    public func postTransfer(
        from: MoneyAccountMO,
        to: MoneyAccountMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String? = nil
    ) throws -> TransactionMO {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard from.objectID != to.objectID else { throw ValidationError.invalidState("Source and destination must differ.") }
        guard from.currencyCode == to.currencyCode else {
            throw ValidationError.invalidState("Cross-currency transfers need an exchange rate; convert manually for now.")
        }
        try ensureActive(from)
        try ensureActive(to)
        let fromLedger = try ledger(for: from)
        let toLedger = try ledger(for: to)
        let journal = try JournalBuilder.build(kind: .transfer, date: date, memo: memo, lines: [
            PostingLine(ledgerAccountCode: toLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: from.currency)),
            PostingLine(ledgerAccountCode: fromLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: from.currency)),
        ])
        let scope = from.scope
        return try persist(
            kind: .transfer, journalKind: .transfer, journal: journal, scope: scope,
            account: nil, category: nil, fromAccount: from, toAccount: to,
            memo: memo, notes: notes, counterpartyName: nil, referenceNo: nil
        )
    }

    /// Personal → business funding. A transfer of claims, never revenue.
    public func postOwnerContribution(
        from personalAccount: MoneyAccountMO,
        to businessAccount: MoneyAccountMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String? = nil
    ) throws -> TransactionMO {
        try validateCrossScope(from: personalAccount, to: businessAccount, amountMinor: amountMinor)
        let fromLedger = try ledger(for: personalAccount)
        let toLedger = try ledger(for: businessAccount)
        let journal = try JournalBuilder.build(kind: .ownerContribution, date: date, memo: memo, lines: [
            PostingLine(ledgerAccountCode: toLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: personalAccount.currency)),
            PostingLine(ledgerAccountCode: fromLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: personalAccount.currency)),
        ])
        return try persist(
            kind: .ownerContribution, journalKind: .ownerContribution, journal: journal,
            scope: businessAccount.scope, account: nil, category: nil,
            fromAccount: personalAccount, toAccount: businessAccount,
            memo: memo, notes: notes, counterpartyName: nil, referenceNo: nil
        )
    }

    /// Business → personal payout. A distribution, never an expense.
    public func postOwnerWithdrawal(
        from businessAccount: MoneyAccountMO,
        to personalAccount: MoneyAccountMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String? = nil
    ) throws -> TransactionMO {
        try validateCrossScope(from: businessAccount, to: personalAccount, amountMinor: amountMinor)
        let fromLedger = try ledger(for: businessAccount)
        let toLedger = try ledger(for: personalAccount)
        let journal = try JournalBuilder.build(kind: .ownerWithdrawal, date: date, memo: memo, lines: [
            PostingLine(ledgerAccountCode: toLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: businessAccount.currency)),
            PostingLine(ledgerAccountCode: fromLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: businessAccount.currency)),
        ])
        return try persist(
            kind: .ownerWithdrawal, journalKind: .ownerWithdrawal, journal: journal,
            scope: businessAccount.scope, account: nil, category: nil,
            fromAccount: businessAccount, toAccount: personalAccount,
            memo: memo, notes: notes, counterpartyName: nil, referenceNo: nil
        )
    }

    // MARK: - Update / Delete

    /// Rebuilds a simple transaction (income/expense) in place.
    public func updateSimple(
        _ transaction: TransactionMO,
        account: MoneyAccountMO,
        category: CategoryMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String?,
        counterpartyName: String?,
        referenceNo: String?
    ) throws {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard let scope = transaction.scope else { throw ValidationError.invalidState("The transaction has no scope.") }
        clearJournal(transaction)
        transaction.updatedAt = .now
        transaction.postedAt = date
        transaction.dateKey = Int32(DateKey.make(from: date))
        transaction.amountMinor = amountMinor
        transaction.currencyCode = account.currencyCode
        transaction.memo = memo
        transaction.notes = notes
        transaction.referenceNo = referenceNo
        transaction.account = account
        transaction.category = category
        transaction.counterparty = try counterparty(named: counterpartyName)

        switch transaction.kind {
        case .expense:
            let categoryLedger = try ledger(for: category)
            let accountLedger = try ledger(for: account)
            let journal = try JournalBuilder.build(kind: .expense, date: date, memo: memo, lines: [
                PostingLine(ledgerAccountCode: categoryLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: account.currency)),
                PostingLine(ledgerAccountCode: accountLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: account.currency)),
            ])
            try attachJournal(journal, kind: .expense, to: transaction)
        case .income:
            let categoryLedger = try ledger(for: category)
            let accountLedger = try ledger(for: account)
            let journal = try JournalBuilder.build(kind: .income, date: date, memo: memo, lines: [
                PostingLine(ledgerAccountCode: accountLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: account.currency)),
                PostingLine(ledgerAccountCode: categoryLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: account.currency)),
            ])
            try attachJournal(journal, kind: .income, to: transaction)
        default:
            throw ValidationError.invalidState("Only income and expense transactions are editable here.")
        }
        try controller.saveViewContext()
    }

    /// Rebuilds a transfer/owner transfer in place.
    public func updateTransfer(
        _ transaction: TransactionMO,
        from: MoneyAccountMO,
        to: MoneyAccountMO,
        amountMinor: Int64,
        date: Date,
        memo: String?,
        notes: String?
    ) throws {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard from.currencyCode == to.currencyCode else {
            throw ValidationError.invalidState("Cross-currency transfers need an exchange rate; convert manually for now.")
        }
        clearJournal(transaction)
        transaction.updatedAt = .now
        transaction.postedAt = date
        transaction.dateKey = Int32(DateKey.make(from: date))
        transaction.amountMinor = amountMinor
        transaction.currencyCode = from.currencyCode
        transaction.memo = memo
        transaction.notes = notes
        transaction.fromAccount = from
        transaction.toAccount = to

        let fromLedger = try ledger(for: from)
        let toLedger = try ledger(for: to)
        let journalKind: JournalKind
        switch transaction.kind {
        case .ownerContribution: journalKind = .ownerContribution
        case .ownerWithdrawal: journalKind = .ownerWithdrawal
        default: journalKind = .transfer
        }
        let journal = try JournalBuilder.build(kind: journalKind, date: date, memo: memo, lines: [
            PostingLine(ledgerAccountCode: toLedger.code, direction: .debit, money: Money(minorUnits: amountMinor, currency: from.currency)),
            PostingLine(ledgerAccountCode: fromLedger.code, direction: .credit, money: Money(minorUnits: amountMinor, currency: from.currency)),
        ])
        try attachJournal(journal, kind: journalKind, to: transaction)
        try controller.saveViewContext()
    }

    /// Deletes the transaction together with its journal (history rows
    /// cascade), keeping every other balance intact.
    public func delete(_ transaction: TransactionMO) throws {
        if let journal = transaction.journal {
            context.delete(journal)
        }
        context.delete(transaction)
        try controller.saveViewContext()
    }

    // MARK: - Internals

    private func persist(
        kind: TransactionKind,
        journalKind: JournalKind,
        journal: BalancedJournal,
        scope: FinancialScopeMO?,
        account: MoneyAccountMO?,
        category: CategoryMO?,
        fromAccount: MoneyAccountMO?,
        toAccount: MoneyAccountMO?,
        memo: String?,
        notes: String?,
        counterpartyName: String?,
        referenceNo: String?
    ) throws -> TransactionMO {
        let transaction = TransactionMO(context: context)
        transaction.id = UUID()
        transaction.kind = kind
        transaction.postedAt = journal.date
        transaction.dateKey = Int32(DateKey.make(from: journal.date))
        transaction.amountMinor = journal.lines.first?.money.minorUnits ?? 0
        transaction.currencyCode = journal.lines.first?.money.currency.code ?? "IRR"
        transaction.memo = memo
        transaction.notes = notes
        transaction.referenceNo = referenceNo
        transaction.createdAt = .now
        transaction.updatedAt = .now
        transaction.scope = scope
        transaction.account = account
        transaction.category = category
        transaction.fromAccount = fromAccount
        transaction.toAccount = toAccount
        transaction.counterparty = try counterparty(named: counterpartyName)
        try attachJournal(journal, kind: journalKind, to: transaction)
        try controller.saveViewContext()
        return transaction
    }

    private func attachJournal(_ balanced: BalancedJournal, kind: JournalKind, to transaction: TransactionMO) throws {
        let journal = JournalMO(context: context)
        journal.id = UUID()
        journal.kind = kind
        journal.date = balanced.date
        journal.createdAt = .now
        journal.memo = balanced.memo
        journal.transaction = transaction
        transaction.journal = journal

        var ledgersByCode: [String: LedgerAccountMO] = [:]
        for line in balanced.lines {
            let ledger = try ledgersByCode[line.ledgerAccountCode] ?? lookupLedger(code: line.ledgerAccountCode)
            let row = LedgerLineMO(context: context)
            row.id = UUID()
            row.direction = line.direction
            row.amountMinor = line.money.minorUnits
            row.currencyCode = line.money.currency.code
            row.journal = journal
            row.ledgerAccount = ledger
        }
    }

    private func clearJournal(_ transaction: TransactionMO) {
        if let journal = transaction.journal {
            context.delete(journal)
        }
        transaction.journal = nil
    }

    private func lookupLedger(code: String) throws -> LedgerAccountMO {
        let request = LedgerAccountMO.fetchRequest()
        request.predicate = NSPredicate(format: "code == %@", code)
        request.fetchLimit = 1
        guard let ledger = try context.fetch(request).first else {
            throw AccountingError.unknownLedgerAccount(code: code)
        }
        return ledger
    }

    private func ledger(for account: MoneyAccountMO) throws -> LedgerAccountMO {
        try AccountRepository.ensureAssetLedger(for: account, in: context)
    }

    private func ledger(for category: CategoryMO) throws -> LedgerAccountMO {
        if let existing = category.ledgerAccount { return existing }
        let created = try AccountRepository.ensureLedgerAccount(
            code: category.kind == .income
                ? ChartOfAccounts.incomeCategoryCode(forCategoryID: category.id)
                : ChartOfAccounts.expenseCategoryCode(forCategoryID: category.id),
            name: category.name,
            type: category.kind == .income ? .income : .expense,
            normalSide: category.kind == .income ? .credit : .debit,
            in: context
        )
        category.ledgerAccount = created
        return created
    }

    private func counterparty(named name: String?) throws -> CounterpartyMO? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let request = CounterpartyMO.fetchRequest()
        request.predicate = NSPredicate(format: "displayName ==[cd] %@", trimmed)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let counterparty = CounterpartyMO(context: context)
        counterparty.id = UUID()
        counterparty.displayName = trimmed
        counterparty.kind = .person
        return counterparty
    }

    private func ensureActive(_ account: MoneyAccountMO) throws {
        guard account.status == .active else {
            throw ValidationError.invalidState("The account “\(account.name)” is archived.")
        }
    }

    private func validateCrossScope(from: MoneyAccountMO, to: MoneyAccountMO, amountMinor: Int64) throws {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard from.objectID != to.objectID else { throw ValidationError.invalidState("Source and destination must differ.") }
        guard from.currencyCode == to.currencyCode else {
            throw ValidationError.invalidState("Cross-currency owner transfers need an exchange rate; convert manually for now.")
        }
        try ensureActive(from)
        try ensureActive(to)
    }
}
