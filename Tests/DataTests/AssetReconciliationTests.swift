import CoreData
import Foundation
import ProMeData
import ProMeDomain
import Testing

/// M7 scenarios: asset capitalization and sale with gain/loss, valuations,
/// and bank-statement reconciliation.
@Suite("Assets & reconciliation")
@MainActor
struct AssetReconciliationTests {
    struct World {
        let controller: PersistenceController
        let scopes: ScopeRepository
        let accounts: AccountRepository
        let posting: PostingService
        let categories: CategoryRepository
        let aggregates: AggregateQueries
        let assets: AssetService
        let reconciliation: ReconciliationService
        let personal: FinancialScopeMO
        let bank: MoneyAccountMO
    }

    private func makeWorld() throws -> World {
        let controller = try PersistenceController(inMemory: true)
        let scopes = ScopeRepository(controller: controller)
        let accounts = AccountRepository(controller: controller)
        let posting = PostingService(controller: controller)
        let categories = CategoryRepository(controller: controller)
        let personal = try scopes.ensurePersonalScope()
        let bank = try accounts.create(AccountRepository.Draft(name: "Bank A", openingBalanceMinor: 10_000_000), in: personal)
        return World(
            controller: controller, scopes: scopes, accounts: accounts, posting: posting,
            categories: categories,
            aggregates: AggregateQueries(controller: controller),
            assets: AssetService(controller: controller),
            reconciliation: ReconciliationService(controller: controller),
            personal: personal, bank: bank
        )
    }

    private func balance(_ world: World, _ account: MoneyAccountMO) -> Int64 {
        (try? world.aggregates.accountBalance(account)) ?? -1
    }

    private func ledger(_ world: World, code: String) throws -> Int64 {
        let ledger = try AccountRepository.ensureLedgerAccount(
            code: code, name: code, type: .asset, normalSide: .debit,
            in: world.controller.container.viewContext
        )
        return try world.aggregates.ledgerBalance(ledger)
    }

    @Test("Buying a laptop from the bank capitalises it instead of expensing")
    func assetPurchaseCapitalises() throws {
        let world = try makeWorld()
        let asset = try world.assets.create(
            AssetService.NewAsset(
                name: "Laptop", type: .electronics,
                purchasePriceMinor: 100_000_000, purchaseDate: .now,
                currency: .irr, fundingAccount: world.bank
            ),
            in: world.personal
        )
        #expect(balance(world, world.bank) == 10_000_000 - 100_000_000)
        let fixed = try ledger(world, code: ChartOfAccounts.fixedAssetCode(forAssetID: asset.id))
        #expect(fixed == 100_000_000)

        // The expense sums stay untouched by the purchase.
        let expense = try world.aggregates.sum(kind: .expense, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(expense.isEmpty)
    }

    @Test("Selling above book value books a gain; below books a loss")
    func assetSaleGainAndLoss() throws {
        let world = try makeWorld()
        let asset = try world.assets.create(
            AssetService.NewAsset(
                name: "Phone", type: .electronics,
                purchasePriceMinor: 5_000_000, currency: .irr, fundingAccount: world.bank
            ),
            in: world.personal
        )
        try world.assets.sell(asset, account: world.bank, proceedsMinor: 6_000_000, date: .now)
        #expect(asset.status == .sold)
        #expect(balance(world, world.bank) == 10_000_000 - 5_000_000 + 6_000_000)
        #expect(try ledger(world, code: ChartOfAccounts.assetGainCode) == -1_000_000)  // credit balance = gain
        #expect(try ledger(world, code: ChartOfAccounts.fixedAssetCode(forAssetID: asset.id)) == 0)

        let second = try world.assets.create(
            AssetService.NewAsset(
                name: "Watch", type: .electronics,
                purchasePriceMinor: 4_000_000, currency: .irr, fundingAccount: world.bank
            ),
            in: world.personal
        )
        try world.assets.sell(second, account: world.bank, proceedsMinor: 3_000_000, date: .now)
        #expect(try ledger(world, code: ChartOfAccounts.assetLossCode) == 1_000_000)  // debit = loss
    }

    @Test("Valuations update the current value and keep history")
    func valuations() throws {
        let world = try makeWorld()
        let asset = try world.assets.create(
            AssetService.NewAsset(name: "Car", type: .vehicle, purchasePriceMinor: 900_000_000, currency: .irr),
            in: world.personal
        )
        try world.assets.recordValuation(asset, valueMinor: 850_000_000, date: .now)
        #expect(asset.currentValueMinor == 850_000_000)
        #expect(asset.valuations.count == 1)
        let totals = try world.assets.totals(scope: world.personal)
        #expect(totals.first?.minor == 850_000_000)
    }

    @Test("Reconciliation matches the ledger at a date and marks transactions")
    func reconciliationFlow() throws {
        let world = try makeWorld()
        let past = Date(timeIntervalSinceNow: -86_400 * 5)
        let future = Date(timeIntervalSinceNow: 86_400 * 5)
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: try world.categories.create(name: "Food", kind: .expense, parent: nil),
            amountMinor: 300_000, date: past, memo: "Past expense"
        )
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: try world.categories.create(name: "Tickets", kind: .expense, parent: nil),
            amountMinor: 200_000, date: future, memo: "Future expense"
        )

        let asOf = Date()
        let exclusive = Calendar.current.startOfDay(for: asOf).addingTimeInterval(86_400)
        let appBalance = try world.reconciliation.appBalance(account: world.bank, before: exclusive)
        // Opening 10M − past 300k only; the future expense is excluded.
        #expect(appBalance == 9_700_000)

        let unreconciled = try world.reconciliation.unreconciled(account: world.bank, before: exclusive)
        #expect(unreconciled.count == 1)

        let record = try world.reconciliation.reconcile(
            account: world.bank, asOf: asOf, bankBalanceMinor: 9_700_000,
            marking: unreconciled
        )
        #expect(record.differenceMinor == 0)
        #expect(unreconciled[0].isReconciled)
        #expect(world.reconciliation.latest(account: world.bank) != nil)

        // Marking a transaction from another account is refused.
        let otherAccount = try world.accounts.create(AccountRepository.Draft(name: "Cash", type: .cash), in: world.personal)
        let stray = try world.posting.postExpense(
            scope: world.personal, account: otherAccount, category: try world.categories.allCategories(kind: .expense)[0],
            amountMinor: 1_000, date: .now, memo: nil
        )
        #expect(throws: ValidationError.self) {
            try world.reconciliation.reconcile(
                account: world.bank, asOf: asOf, bankBalanceMinor: 9_700_000, marking: [stray]
            )
        }
    }
}
