import CoreData
import Foundation
import ProMeDomain

@objc(RecurringTransactionMO)
public final class RecurringTransactionMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringTransactionMO> {
        NSFetchRequest<RecurringTransactionMO>(entityName: "RecurringTransaction")
    }

    @NSManaged public var id: UUID
    @NSManaged public var kindRaw: String
    @NSManaged public var amountMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var frequencyRaw: String
    @NSManaged public var interval: Int32
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date?
    @NSManaged public var nextDueAt: Date
    @NSManaged public var lastPostedAt: Date?
    @NSManaged public var autoPost: Bool
    @NSManaged public var memo: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var account: MoneyAccountMO?
    @NSManaged public var category: CategoryMO?
    @NSManaged public var insurance: InsuranceMO?

    public var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    public var rule: RecurrenceRule {
        get { RecurrenceRule(frequency: frequency, interval: Int(interval)) }
        set {
            frequency = newValue.frequency
            interval = Int32(max(1, newValue.interval))
        }
    }
}

@objc(BudgetEntryMO)
public final class BudgetEntryMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BudgetEntryMO> {
        NSFetchRequest<BudgetEntryMO>(entityName: "BudgetEntry")
    }

    @NSManaged public var id: UUID
    @NSManaged public var monthKey: Int32
    @NSManaged public var amountMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var createdAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var category: CategoryMO?
}

