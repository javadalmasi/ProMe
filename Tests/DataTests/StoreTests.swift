import CoreData
import Foundation
import ProMeData
import ProMeDomain
import Testing

@Suite("Core Data store")
@MainActor
struct StoreTests {
    @Test("Model loads from the package bundle with every v5 entity")
    func modelLoads() throws {
        let model = try PersistenceController.loadModel()
        #expect(model.entities.count == 29)
        for name in ["FinancialScope", "Business", "UserProfile", "MoneyAccount", "LedgerAccount",
                     "Journal", "LedgerLine", "Category", "Tag", "Counterparty", "Transaction", "Attachment",
                     "RecurringTransaction", "BudgetEntry",
                     "Debt", "DebtPayment", "Loan", "LoanInstallment", "Insurance",
                     "Asset", "AssetValuation", "Reconciliation",
                     "TaskItem", "ActivityEntry", "AlertItem", "Appointment", "Note", "Place",
                     "DeletionLog"] {
            #expect(model.entitiesByName[name] != nil, "missing entity \(name)")
        }
    }

    @Test("In-memory store persists a scope, an account and a balanced journal")
    func persistsBalancedJournal() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let scope = FinancialScopeMO(context: context)
        scope.id = UUID()
        scope.name = "Personal"
        scope.kind = .personal
        scope.isActive = true
        scope.createdAt = Date(timeIntervalSince1970: 1_790_000_000)

        let account = MoneyAccountMO(context: context)
        account.id = UUID()
        account.name = "Bank A"
        account.type = .current
        account.currencyCode = "IRR"
        account.openingBalanceMinor = 5_000_000
        account.openedAt = .now
        account.status = .active
        account.position = 0
        account.createdAt = .now
        account.updatedAt = .now
        account.scope = scope

        let assetLedger = LedgerAccountMO(context: context)
        assetLedger.id = UUID()
        assetLedger.code = ChartOfAccounts.assetAccountCode(forAccountID: account.id)
        assetLedger.name = "Bank A"
        assetLedger.type = .asset
        assetLedger.normalSide = .debit
        assetLedger.createdAt = .now
        account.ledgerAccount = assetLedger

        let incomeLedger = LedgerAccountMO(context: context)
        incomeLedger.id = UUID()
        incomeLedger.code = ChartOfAccounts.incomeCategoryCode(forCategoryID: UUID())
        incomeLedger.name = "Salary"
        incomeLedger.type = .income
        incomeLedger.normalSide = .credit
        incomeLedger.createdAt = .now

        let journal = JournalMO(context: context)
        journal.id = UUID()
        journal.kind = .income
        journal.date = .now
        journal.createdAt = .now
        journal.memo = nil

        let debit = LedgerLineMO(context: context)
        debit.id = UUID()
        debit.direction = .debit
        debit.amountMinor = 750_000
        debit.currencyCode = "IRR"
        debit.journal = journal
        debit.ledgerAccount = assetLedger

        let credit = LedgerLineMO(context: context)
        credit.id = UUID()
        credit.direction = .credit
        credit.amountMinor = 750_000
        credit.currencyCode = "IRR"
        credit.journal = journal
        credit.ledgerAccount = incomeLedger

        try controller.saveViewContext()

        let scopes = try context.fetch(FinancialScopeMO.fetchRequest())
        #expect(scopes.count == 1)
        #expect(scopes.first?.accounts.count == 1)
        #expect(scopes.first?.kind == .personal)

        let lines = try context.fetch(LedgerLineMO.fetchRequest())
        #expect(lines.count == 2)

        // The journal itself must be balanced: debits minus credits sum to zero.
        let journalDelta = lines.reduce(Int64(0)) { partial, line in
            line.direction == .debit ? partial + line.amountMinor : partial - line.amountMinor
        }
        #expect(journalDelta == 0)

        // The asset account's own ledger keeps its debit and gains 750,000.
        let assetDelta = assetLedger.lines.reduce(Int64(0)) { partial, line in
            line.direction == .debit ? partial + line.amountMinor : partial - line.amountMinor
        }
        #expect(assetDelta == 750_000)
        #expect(account.openingBalanceMinor + assetDelta == 5_750_000)
    }

    @Test("Deleting a journal cascades to its lines")
    func cascadesJournalDeletion() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let ledgerAccount = LedgerAccountMO(context: context)
        ledgerAccount.id = UUID()
        ledgerAccount.code = "AST.test"
        ledgerAccount.name = "Test"
        ledgerAccount.type = .asset
        ledgerAccount.normalSide = .debit
        ledgerAccount.createdAt = .now

        let journal = JournalMO(context: context)
        journal.id = UUID()
        journal.kind = .adjustment
        journal.date = .now
        journal.createdAt = .now

        let line = LedgerLineMO(context: context)
        line.id = UUID()
        line.direction = .debit
        line.amountMinor = 1
        line.currencyCode = "IRR"
        line.journal = journal
        line.ledgerAccount = ledgerAccount

        try controller.saveViewContext()
        context.delete(journal)
        try controller.saveViewContext()

        #expect(try context.count(for: JournalMO.fetchRequest()) == 0)
        #expect(try context.count(for: LedgerLineMO.fetchRequest()) == 0)
    }
}
