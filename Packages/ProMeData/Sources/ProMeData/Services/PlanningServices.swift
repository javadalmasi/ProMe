import CoreData
import Foundation
import ProMeDomain

/// Runs recurring transactions: catch-up posting on launch and manual
/// "post now". Never throws outward past what the caller can show.
@MainActor
public final class RecurringService {
    private let controller: PersistenceController
    private let posting: PostingService
    public init(controller: PersistenceController, posting: PostingService) {
        self.controller = controller
        self.posting = posting
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func all() throws -> [RecurringTransactionMO] {
        let request = RecurringTransactionMO.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "nextDueAt", ascending: true)]
        return try context.fetch(request)
    }

    public struct Draft {
        public var kind: TransactionKind
        public var amountMinor: Int64
        public var account: MoneyAccountMO
        public var category: CategoryMO?
        public var frequency: RecurrenceFrequency
        public var interval: Int
        public var startDate: Date
        public var endDate: Date?
        public var autoPost: Bool
        public var memo: String?

        public init(
            kind: TransactionKind = .expense,
            amountMinor: Int64,
            account: MoneyAccountMO,
            category: CategoryMO? = nil,
            frequency: RecurrenceFrequency = .monthly,
            interval: Int = 1,
            startDate: Date = .now,
            endDate: Date? = nil,
            autoPost: Bool = true,
            memo: String? = nil
        ) {
            self.kind = kind
            self.amountMinor = amountMinor
            self.account = account
            self.category = category
            self.frequency = frequency
            self.interval = interval
            self.startDate = startDate
            self.endDate = endDate
            self.autoPost = autoPost
            self.memo = memo
        }
    }

    public func create(_ draft: Draft, in scope: FinancialScopeMO) throws -> RecurringTransactionMO {
        guard draft.amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        let recurring = RecurringTransactionMO(context: context)
        recurring.id = UUID()
        recurring.kind = draft.kind
        recurring.amountMinor = draft.amountMinor
        recurring.currencyCode = draft.account.currencyCode
        recurring.rule = RecurrenceRule(frequency: draft.frequency, interval: draft.interval)
        recurring.startDate = draft.startDate
        recurring.endDate = draft.endDate
        recurring.autoPost = draft.autoPost
        recurring.memo = draft.memo
        recurring.isActive = true
        recurring.createdAt = .now
        recurring.updatedAt = .now
        recurring.scope = scope
        recurring.account = draft.account
        recurring.category = draft.category
        recurring.nextDueAt = draft.startDate
        try controller.saveViewContext()
        return recurring
    }

    public func update(_ recurring: RecurringTransactionMO, draft: Draft) throws {
        guard draft.amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        recurring.kind = draft.kind
        recurring.amountMinor = draft.amountMinor
        recurring.rule = RecurrenceRule(frequency: draft.frequency, interval: draft.interval)
        recurring.startDate = draft.startDate
        recurring.endDate = draft.endDate
        recurring.autoPost = draft.autoPost
        recurring.memo = draft.memo
        recurring.account = draft.account
        recurring.category = draft.category
        recurring.currencyCode = draft.account.currencyCode
        recurring.updatedAt = .now
        if recurring.lastPostedAt == nil {
            recurring.nextDueAt = draft.startDate
        }
        try controller.saveViewContext()
    }

    public func cancel(_ recurring: RecurringTransactionMO) throws {
        recurring.isActive = false
        recurring.updatedAt = .now
        try controller.saveViewContext()
    }

    /// Posts every due recurring transaction (auto-post only) with catch-up
    /// for missed periods, and returns the posted transactions.
    @discardableResult
    public func postDue(asOf date: Date = .now) throws -> [TransactionMO] {
        var posted: [TransactionMO] = []
        for recurring in try all() {
            guard recurring.autoPost else { continue }
            posted.append(contentsOf: try postDue(of: recurring, asOf: date))
        }
        return posted
    }

    /// Posts all due occurrences of one recurring transaction (manual or auto).
    @discardableResult
    public func postDue(of recurring: RecurringTransactionMO, asOf date: Date = .now) throws -> [TransactionMO] {
        var posted: [TransactionMO] = []
        guard let scope = recurring.scope, let account = recurring.account else { return posted }
        let rule = recurring.rule
        var due = recurring.nextDueAt
        var iterations = 0

        while due <= date, recurring.endDate.map({ due < $0 }) ?? true, iterations < 100 {
            iterations += 1
            let transaction: TransactionMO
            switch recurring.kind {
            case .income:
                guard let category = recurring.category else { throw ValidationError.missingField("category") }
                transaction = try posting.postIncome(
                    scope: scope, account: account, category: category,
                    amountMinor: recurring.amountMinor, date: due, memo: recurring.memo
                )
            default:
                guard let category = recurring.category else { throw ValidationError.missingField("category") }
                transaction = try posting.postExpense(
                    scope: scope, account: account, category: category,
                    amountMinor: recurring.amountMinor, date: due, memo: recurring.memo
                )
            }
            posted.append(transaction)
            recurring.lastPostedAt = due
            guard let next = rule.next(after: due, from: recurring.startDate, calendar: .current) else { break }
            due = next
        }
        recurring.nextDueAt = due
        recurring.updatedAt = .now
        try controller.saveViewContext()
        return posted
    }

    /// Recurring payments due within the next `days` days, for the
    /// dashboard and reminders.
    public func upcoming(withinDays days: Int, asOf date: Date = .now) throws -> [RecurringTransactionMO] {
        let request = RecurringTransactionMO.fetchRequest()
        request.predicate = NSPredicate(
            format: "isActive == YES AND nextDueAt >= %@ AND nextDueAt < %@",
            date as NSDate,
            Calendar.current.date(byAdding: .day, value: max(1, days), to: date)! as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "nextDueAt", ascending: true)]
        return try context.fetch(request)
    }
}

/// Budget actuals: spent per category within a display-calendar month.
@MainActor
public final class BudgetService {
    private let controller: PersistenceController
    private let aggregates: AggregateQueries
    public init(controller: PersistenceController, aggregates: AggregateQueries) {
        self.controller = controller
        self.aggregates = aggregates
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public struct Row: Identifiable {
        public var id: UUID { entry.id }
        public let entry: BudgetEntryMO
        public let spentMinor: Int64
        public var remainingMinor: Int64 { entry.amountMinor - spentMinor }
        public var fractionUsed: Double {
            guard entry.amountMinor > 0 else { return 0 }
            return Double(spentMinor) / Double(entry.amountMinor)
        }
    }

    /// monthKey is computed in the user's display calendar (yyyyMM).
    public static func monthKey(for date: Date, preference: CalendarPreference) -> Int32 {
        let resolver = PeriodResolver(preference: preference)
        let parts = resolver.calendar.dateComponents([.year, .month], from: date)
        return Int32((parts.year ?? 0) * 100 + (parts.month ?? 0))
    }

    public func entries(monthKey: Int32, scope: FinancialScopeMO?) throws -> [BudgetEntryMO] {
        let request = BudgetEntryMO.fetchRequest()
        var clauses = [NSPredicate(format: "monthKey == %d", monthKey)]
        if let scope {
            clauses.append(NSPredicate(format: "scope == %@", scope))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    public func setBudget(category: CategoryMO, scope: FinancialScopeMO, monthKey: Int32, amountMinor: Int64, currency: Currency) throws {
        guard amountMinor >= 0 else { throw ValidationError.invalidAmount("Budgets cannot be negative.") }
        let existing = try entries(monthKey: monthKey, scope: scope).first { $0.category?.objectID == category.objectID }
        if let existing {
            if amountMinor == 0 {
                context.delete(existing)
            } else {
                existing.amountMinor = amountMinor
            }
        } else {
            let entry = BudgetEntryMO(context: context)
            entry.id = UUID()
            entry.monthKey = monthKey
            entry.amountMinor = amountMinor
            entry.currencyCode = currency.code
            entry.createdAt = .now
            entry.scope = scope
            entry.category = category
        }
        try controller.saveViewContext()
    }

    /// Rows with actual spend for the month. Children roll up into their
    /// parent category when the budget sits on a parent.
    public func rows(monthKey: Int32, scope: FinancialScopeMO?, from: Date, to: Date) throws -> [Row] {
        let spent = try aggregates.sumByCategory(kind: .expense, scope: scope, from: from, to: to)
        var spentByID: [UUID: Int64] = [:]
        for sum in spent where sum.currencyCode == "IRR" {
            if let id = sum.categoryID {
                spentByID[id, default: 0] += sum.minor
            }
        }
        var result: [Row] = []
        for entry in try entries(monthKey: monthKey, scope: scope) {
            var total = spentByID[entry.category?.id ?? UUID()] ?? 0
            for child in entry.category?.children ?? [] {
                total += spentByID[child.id] ?? 0
            }
            result.append(Row(entry: entry, spentMinor: total))
        }
        return result
    }
}
