import CoreData
import Foundation
import ProMeDomain

/// Physical assets for the net worth picture. A purchase funded from an
/// account is capitalized (Dr Fixed Asset / Cr account) — never expensed;
/// selling books the difference between proceeds and book value as gain
/// or loss.
@MainActor
public final class AssetService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func all(scope: FinancialScopeMO?, includeSold: Bool = false) throws -> [AssetMO] {
        let request = AssetMO.fetchRequest()
        var clauses: [NSPredicate] = []
        if let scope {
            clauses.append(NSPredicate(format: "scope == %@", scope))
        }
        if !includeSold {
            clauses.append(NSPredicate(format: "statusRaw == %@", AssetStatus.owned.rawValue))
        }
        request.predicate = clauses.isEmpty
            ? NSPredicate(value: true)
            : NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [NSSortDescriptor(key: "purchaseDate", ascending: false)]
        return try context.fetch(request)
    }

    public struct NewAsset {
        public var name: String
        public var type: AssetType
        public var purchasePriceMinor: Int64
        public var purchaseDate: Date
        public var currency: Currency
        public var fundingAccount: MoneyAccountMO?
        public var notes: String?

        public init(
            name: String,
            type: AssetType = .other,
            purchasePriceMinor: Int64,
            purchaseDate: Date = .now,
            currency: Currency = .irr,
            fundingAccount: MoneyAccountMO? = nil,
            notes: String? = nil
        ) {
            self.name = name
            self.type = type
            self.purchasePriceMinor = purchasePriceMinor
            self.purchaseDate = purchaseDate
            self.currency = currency
            self.fundingAccount = fundingAccount
            self.notes = notes
        }
    }

    public func create(_ draft: NewAsset, in scope: FinancialScopeMO) throws -> AssetMO {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingField("name") }
        guard draft.purchasePriceMinor >= 0 else { throw ValidationError.invalidAmount("Values cannot be negative.") }

        let asset = AssetMO(context: context)
        asset.id = UUID()
        asset.name = name
        asset.type = draft.type
        asset.purchasePriceMinor = draft.purchasePriceMinor
        asset.purchaseDate = draft.purchaseDate
        asset.currentValueMinor = draft.purchasePriceMinor
        asset.valuationDate = draft.purchaseDate
        asset.currencyCode = draft.fundingAccount?.currencyCode ?? draft.currency.code
        asset.status = .owned
        asset.notes = draft.notes
        asset.createdAt = .now
        asset.scope = scope

        if let funding = draft.fundingAccount {
            guard funding.status == .active else { throw ValidationError.invalidState("The funding account is archived.") }
            let fixedAsset = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.fixedAssetCode(forAssetID: asset.id),
                name: "Asset: \(name)",
                type: .asset,
                normalSide: .debit,
                in: context
            )
            let money = Money(minorUnits: draft.purchasePriceMinor, currency: funding.currency)
            let balanced = try JournalBuilder.build(kind: .assetPurchase, date: draft.purchaseDate, memo: name, lines: [
                PostingLine(ledgerAccountCode: fixedAsset.code, direction: .debit, money: money),
                PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: funding, in: context).code, direction: .credit, money: money),
            ])
            asset.journal = try Self.attach(balanced, kind: .assetPurchase, asset: asset, in: context)
        }
        try controller.saveViewContext()
        return asset
    }

    public func rename(_ asset: AssetMO, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.missingField("name") }
        asset.name = trimmed
        if asset.journal?.memo == asset.name || asset.journal?.memo != nil {
            asset.journal?.memo = trimmed
        }
        try controller.saveViewContext()
    }

    /// Records a re-valuation (no ledger impact — the books carry cost).
    public func recordValuation(_ asset: AssetMO, valueMinor: Int64, date: Date, notes: String? = nil) throws {
        guard valueMinor >= 0 else { throw ValidationError.invalidAmount("Values cannot be negative.") }
        asset.currentValueMinor = valueMinor
        asset.valuationDate = date
        let valuation = AssetValuationMO(context: context)
        valuation.id = UUID()
        valuation.valueMinor = valueMinor
        valuation.date = date
        valuation.notes = notes
        valuation.createdAt = .now
        valuation.asset = asset
        try controller.saveViewContext()
    }

    /// Selling: Dr account (proceeds) / Cr Fixed Asset (book value), with
    /// the difference booked as gain (income) or loss (expense).
    public func sell(_ asset: AssetMO, account: MoneyAccountMO, proceedsMinor: Int64, date: Date) throws {
        guard asset.status == .owned else { throw ValidationError.invalidState("This asset is already sold.") }
        guard proceedsMinor >= 0 else { throw ValidationError.invalidAmount("Proceeds cannot be negative.") }
        guard account.currencyCode == asset.currencyCode else {
            throw ValidationError.invalidState("The account currency must match the asset currency.")
        }

        let fixedAsset = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.fixedAssetCode(forAssetID: asset.id),
            name: "Asset",
            type: .asset,
            normalSide: .debit,
            in: context
        )
        let bookValue = asset.currentValueMinor
        let proceeds = Money(minorUnits: proceedsMinor, currency: account.currency)
        var lines: [PostingLine] = [
            PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: account, in: context).code, direction: .debit, money: proceeds),
        ]
        if proceedsMinor > bookValue {
            let gainLedger = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.assetGainCode, name: "Gain on Sale",
                type: .income, normalSide: .credit, in: context
            )
            let gain = Money(minorUnits: proceedsMinor - bookValue, currency: account.currency)
            lines.append(PostingLine(ledgerAccountCode: gainLedger.code, direction: .credit, money: gain))
        } else if proceedsMinor < bookValue {
            let lossLedger = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.assetLossCode, name: "Loss on Sale",
                type: .expense, normalSide: .debit, in: context
            )
            let loss = Money(minorUnits: bookValue - proceedsMinor, currency: account.currency)
            lines.append(PostingLine(ledgerAccountCode: lossLedger.code, direction: .debit, money: loss))
        }
        lines.append(PostingLine(ledgerAccountCode: fixedAsset.code, direction: .credit, money: Money(minorUnits: bookValue, currency: account.currency)))

        let balanced = try JournalBuilder.build(kind: .assetSale, date: date, memo: asset.name, lines: lines)
        asset.saleJournal = try Self.attach(balanced, kind: .assetSale, asset: asset, in: context)
        asset.status = .sold
        asset.soldAt = date
        try controller.saveViewContext()
    }

    public func delete(_ asset: AssetMO) throws {
        if let journal = asset.journal {
            context.delete(journal)
        }
        if let saleJournal = asset.saleJournal {
            context.delete(saleJournal)
        }
        context.delete(asset)
        try controller.saveViewContext()
    }

    /// Owned-asset value totals per currency, for net worth.
    public func totals(scope: FinancialScopeMO?) throws -> [AggregateQueries.CurrencySum] {
        var sums: [String: Int64] = [:]
        for asset in try all(scope: scope, includeSold: false) {
            sums[asset.currencyCode, default: 0] += asset.currentValueMinor
        }
        return sums.map { AggregateQueries.CurrencySum(currencyCode: $0.key, minor: $0.value) }
            .sorted { $0.currencyCode < $1.currencyCode }
    }

    static func attach(
        _ balanced: BalancedJournal,
        kind: JournalKind,
        asset: AssetMO,
        in context: NSManagedObjectContext
    ) throws -> JournalMO {
        try ObligationPosting.attach(balanced, kind: kind, in: context) { journal in
            journal.asset = asset
        }
    }
}

/// Bank-statement reconciliation: compare the app's ledger balance at a
/// date against the real bank balance, mark matched transactions, and keep
/// a history of reconciliations per account.
@MainActor
public final class ReconciliationService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }
    private var aggregates: AggregateQueries { AggregateQueries(controller: controller) }

    public func latest(account: MoneyAccountMO) -> ReconciliationMO? {
        account.reconciliations.sorted { $0.asOfDate > $1.asOfDate }.first
    }

    public func history(account: MoneyAccountMO) -> [ReconciliationMO] {
        account.reconciliations.sorted { $0.asOfDate > $1.asOfDate }
    }

    /// Ledger balance for everything posted strictly before `exclusive`.
    public func appBalance(account: MoneyAccountMO, before exclusive: Date) throws -> Int64 {
        try aggregates.accountBalance(account, before: exclusive)
    }

    /// Unreconciled transactions of the account posted before `exclusive`.
    public func unreconciled(account: MoneyAccountMO, before exclusive: Date) throws -> [TransactionMO] {
        let request = TransactionMO.fetchRequest()
        request.predicate = NSPredicate(
            format: "(account == %@ OR fromAccount == %@ OR toAccount == %@) AND isReconciled == NO AND postedAt < %@",
            account, account, account, exclusive as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "postedAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Marks the given transactions reconciled and stores the statement
    /// snapshot. The difference stays visible in the history.
    public func reconcile(
        account: MoneyAccountMO,
        asOf: Date,
        bankBalanceMinor: Int64,
        marking transactions: [TransactionMO]
    ) throws -> ReconciliationMO {
        let exclusive = Calendar.current.startOfDay(for: asOf).addingTimeInterval(86_400)
        for transaction in transactions {
            guard transaction.account == account
                || transaction.fromAccount == account
                || transaction.toAccount == account else {
                throw ValidationError.invalidState("One of the marked transactions does not belong to this account.")
            }
            transaction.isReconciled = true
            transaction.updatedAt = .now
        }
        let appBalance = try appBalance(account: account, before: exclusive)
        let record = ReconciliationMO(context: context)
        record.id = UUID()
        record.asOfDate = asOf
        record.bankBalanceMinor = bankBalanceMinor
        record.appBalanceMinor = appBalance
        record.createdAt = .now
        record.account = account
        try controller.saveViewContext()
        return record
    }
}
