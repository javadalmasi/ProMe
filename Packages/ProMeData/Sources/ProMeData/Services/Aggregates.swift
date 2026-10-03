import CoreData
import Foundation
import ProMeDomain

/// Fetches transactions for the transaction list using a Domain query.
@MainActor
public final class TransactionRepository {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func fetch(_ query: TransactionQuery, limit: Int = 2000) throws -> [TransactionMO] {
        let request = TransactionMO.fetchRequest()
        request.predicate = Self.predicate(for: query)
        request.sortDescriptors = Self.sortDescriptors(for: query)
        request.fetchLimit = limit
        return try context.fetch(request)
    }

    public static func predicate(for query: TransactionQuery) -> NSPredicate {
        var clauses: [NSPredicate] = []

        if let scopeID = query.scopeID {
            clauses.append(NSPredicate(
                format: "scope.id == %@ OR fromAccount.scope.id == %@ OR toAccount.scope.id == %@",
                scopeID as CVarArg, scopeID as CVarArg, scopeID as CVarArg
            ))
        }
        if let accountID = query.accountID {
            clauses.append(NSPredicate(
                format: "account.id == %@ OR fromAccount.id == %@ OR toAccount.id == %@",
                accountID as CVarArg, accountID as CVarArg, accountID as CVarArg
            ))
        }
        if let categoryID = query.categoryID {
            clauses.append(NSPredicate(format: "category.id == %@", categoryID as CVarArg))
        }
        if !query.kinds.isEmpty {
            let raw = query.kinds.map(\.rawValue)
            clauses.append(NSPredicate(format: "kindRaw IN %@", raw))
        }
        if let start = query.startDate {
            clauses.append(NSPredicate(format: "postedAt >= %@", start as NSDate))
        }
        if let end = query.endDate {
            clauses.append(NSPredicate(format: "postedAt < %@", end as NSDate))
        }
        if let min = query.minAmountMinor {
            clauses.append(NSPredicate(format: "amountMinor >= %lld", min))
        }
        if let max = query.maxAmountMinor {
            clauses.append(NSPredicate(format: "amountMinor <= %lld", max))
        }
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            clauses.append(NSPredicate(
                format: "memo CONTAINS[cd] %@ OR notes CONTAINS[cd] %@ OR counterparty.displayName CONTAINS[cd] %@ OR category.name CONTAINS[cd] %@",
                text, text, text, text
            ))
        }

        guard !clauses.isEmpty else { return NSPredicate(value: true) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
    }

    public static func sortDescriptors(for query: TransactionQuery) -> [NSSortDescriptor] {
        let key: String
        switch query.sort {
        case .date: key = "postedAt"
        case .amount: key = "amountMinor"
        case .category: key = "category.name"
        case .account: key = "account.name"
        }
        var descriptors = [NSSortDescriptor(key: key, ascending: query.ascending)]
        if query.sort != .date {
            descriptors.append(NSSortDescriptor(key: "postedAt", ascending: query.ascending))
        }
        return descriptors
    }
}

/// Aggregate reads for the dashboard and reports. All sums run through
/// SQLite (NSExpression) instead of loading transactions into memory.
@MainActor
public final class AggregateQueries {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public struct CurrencySum: Equatable, Sendable {
        public var currencyCode: String
        public var minor: Int64
    }

    public struct CategorySum: Equatable, Sendable {
        public var categoryID: UUID?
        public var categoryName: String
        public var currencyCode: String
        public var minor: Int64
    }

    /// Income or expense totals in a period, grouped by currency.
    public func sum(kind: TransactionKind, scope: FinancialScopeMO?, from: Date, to: Date) throws -> [CurrencySum] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Transaction")
        var clauses = [
            NSPredicate(format: "kindRaw == %@", kind.rawValue),
            NSPredicate(format: "postedAt >= %@", from as NSDate),
            NSPredicate(format: "postedAt < %@", to as NSDate),
        ]
        if let scope {
            clauses.append(Self.scopeClause(scope))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)

        let rows = try Self.groupedRows(from: request, context: context, fetch: ["currencyCode"], sum: "amountMinor")
        return rows.map { row in
            CurrencySum(
                currencyCode: row["currencyCode"] as? String ?? "IRR",
                minor: (row["total"] as? NSNumber)?.int64Value ?? 0
            )
        }
        .sorted { $0.currencyCode < $1.currencyCode }
    }

    /// Expense (or income) breakdown by category for a period.
    public func sumByCategory(kind: TransactionKind, scope: FinancialScopeMO?, from: Date, to: Date) throws -> [CategorySum] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Transaction")
        var clauses = [
            NSPredicate(format: "kindRaw == %@", kind.rawValue),
            NSPredicate(format: "postedAt >= %@", from as NSDate),
            NSPredicate(format: "postedAt < %@", to as NSDate),
        ]
        if let scope {
            clauses.append(Self.scopeClause(scope))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)

        let rows = try Self.groupedRows(from: request, context: context, fetch: ["category", "currencyCode"], sum: "amountMinor")
        var result: [CategorySum] = []
        for row in rows {
            let minor = (row["total"] as? NSNumber)?.int64Value ?? 0
            let currency = row["currencyCode"] as? String ?? "IRR"
            let category: CategoryMO?
            if let object = row["category"] as? CategoryMO {
                category = object
            } else if let objectID = row["category"] as? NSManagedObjectID {
                category = (try? context.existingObject(with: objectID)) as? CategoryMO
            } else {
                category = nil
            }
            result.append(CategorySum(
                categoryID: category?.id,
                categoryName: category?.name ?? "—",
                currencyCode: currency,
                minor: minor
            ))
        }
        return result.sorted { $0.minor > $1.minor }
    }

    /// Debit-minus-credit total for a single account's asset ledger.
    public func accountBalance(_ account: MoneyAccountMO) throws -> Int64 {
        guard let ledger = account.ledgerAccount else { return 0 }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LedgerLine")
        request.predicate = NSPredicate(format: "ledgerAccount == %@", ledger)

        let rows = try Self.groupedRows(from: request, context: context, fetch: ["directionRaw"], sum: "amountMinor")
        var balance: Int64 = 0
        for row in rows {
            let total = (row["total"] as? NSNumber)?.int64Value ?? 0
            if row["directionRaw"] as? String == LedgerDirection.credit.rawValue {
                balance -= total
            } else {
                balance += total
            }
        }
        return balance
    }

    /// Ledger balance of an account up to (exclusive) a date — the number
    /// a bank statement at that date should match.
    public func accountBalance(_ account: MoneyAccountMO, before exclusive: Date) throws -> Int64 {
        guard let ledger = account.ledgerAccount else { return 0 }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LedgerLine")
        request.predicate = NSPredicate(
            format: "ledgerAccount == %@ AND journal.date < %@",
            ledger, exclusive as NSDate
        )
        let rows = try Self.groupedRows(from: request, context: context, fetch: ["directionRaw"], sum: "amountMinor")
        var balance: Int64 = 0
        for row in rows {
            let total = (row["total"] as? NSNumber)?.int64Value ?? 0
            if row["directionRaw"] as? String == LedgerDirection.credit.rawValue {
                balance -= total
            } else {
                balance += total
            }
        }
        return balance
    }

    /// Debit-minus-credit balance of any raw ledger account (expenses,
    /// liabilities, receivables…).
    public func ledgerBalance(_ ledger: LedgerAccountMO) throws -> Int64 {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LedgerLine")
        request.predicate = NSPredicate(format: "ledgerAccount == %@", ledger)
        let rows = try Self.groupedRows(from: request, context: context, fetch: ["directionRaw"], sum: "amountMinor")
        var balance: Int64 = 0
        for row in rows {
            let total = (row["total"] as? NSNumber)?.int64Value ?? 0
            if row["directionRaw"] as? String == LedgerDirection.credit.rawValue {
                balance -= total
            } else {
                balance += total
            }
        }
        return balance
    }

    /// Current balance per account (ledger-derived).
    public func accountBalances(_ accounts: [MoneyAccountMO]) throws -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for account in accounts {
            result[account.id] = try accountBalance(account)
        }
        return result
    }

    /// Balance sums across accounts, grouped by currency.
    public func cashTotals(accounts: [MoneyAccountMO]) throws -> [CurrencySum] {
        var sums: [String: Int64] = [:]
        for account in accounts {
            let balance = try accountBalance(account)
            sums[account.currencyCode, default: 0] += balance
        }
        return sums.map { CurrencySum(currencyCode: $0.key, minor: $0.value) }
            .sorted { $0.currencyCode < $1.currencyCode }
    }

    public static func scopeClause(_ scope: FinancialScopeMO) -> NSPredicate {
        NSPredicate(
            format: "scope == %@ OR fromAccount.scope == %@ OR toAccount.scope == %@",
            scope, scope, scope
        )
    }

    /// Runs a grouped-sum fetch with `dictionaryResultType`. Aggregate
    /// fetches must use an untyped request: a typed one bridges its
    /// dictionary rows into managed objects and crashes.
    static func groupedRows(
        from request: NSFetchRequest<NSFetchRequestResult>,
        context: NSManagedObjectContext,
        fetch keys: [String],
        sum keyPath: String
    ) throws -> [[String: Any]] {
        let sum = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: keyPath)])
        let sumDescription = NSExpressionDescription()
        sumDescription.name = "total"
        sumDescription.expression = sum
        sumDescription.expressionResultType = .integer64AttributeType

        request.propertiesToFetch = keys + [sumDescription]
        request.propertiesToGroupBy = keys
        request.resultType = .dictionaryResultType

        let raw = try context.fetch(request)
        return raw.compactMap { $0 as? [String: Any] }
    }
}
