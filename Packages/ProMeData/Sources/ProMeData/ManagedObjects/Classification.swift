import CoreData
import Foundation
import ProMeDomain

@objc(CategoryMO)
public final class CategoryMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryMO> {
        NSFetchRequest<CategoryMO>(entityName: "Category")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var kindRaw: String
    @NSManaged public var symbol: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var isSystem: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var parent: CategoryMO?
    @NSManaged public var children: Set<CategoryMO>
    @NSManaged public var ledgerAccount: LedgerAccountMO?
    @NSManaged public var transactions: Set<TransactionMO>
    @NSManaged public var budgetEntries: Set<BudgetEntryMO>
    @NSManaged public var recurringTransactions: Set<RecurringTransactionMO>

    public var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}

@objc(TagMO)
public final class TagMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TagMO> {
        NSFetchRequest<TagMO>(entityName: "Tag")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var colorHex: String?
    @NSManaged public var transactions: Set<TransactionMO>
}

@objc(CounterpartyMO)
public final class CounterpartyMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CounterpartyMO> {
        NSFetchRequest<CounterpartyMO>(entityName: "Counterparty")
    }

    @NSManaged public var id: UUID
    @NSManaged public var displayName: String
    @NSManaged public var kindRaw: String
    @NSManaged public var notes: String?
    @NSManaged public var transactions: Set<TransactionMO>
    @NSManaged public var debts: Set<DebtMO>

    public var kind: CounterpartyKind {
        get { CounterpartyKind(rawValue: kindRaw) ?? .person }
        set { kindRaw = newValue.rawValue }
    }
}
