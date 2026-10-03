import CoreData
import Foundation
import ProMeDomain

@objc(FinancialScopeMO)
public final class FinancialScopeMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FinancialScopeMO> {
        NSFetchRequest<FinancialScopeMO>(entityName: "FinancialScope")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var kindRaw: String
    @NSManaged public var isActive: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var business: BusinessMO?
    @NSManaged public var accounts: Set<MoneyAccountMO>
    @NSManaged public var transactions: Set<TransactionMO>
    @NSManaged public var categories: Set<CategoryMO>
    @NSManaged public var budgetEntries: Set<BudgetEntryMO>
    @NSManaged public var recurringTransactions: Set<RecurringTransactionMO>
    @NSManaged public var debts: Set<DebtMO>
    @NSManaged public var loans: Set<LoanMO>
    @NSManaged public var insurances: Set<InsuranceMO>
    @NSManaged public var assets: Set<AssetMO>

    public var kind: ScopeKind {
        get { ScopeKind(rawValue: kindRaw) ?? .personal }
        set { kindRaw = newValue.rawValue }
    }
}

@objc(BusinessMO)
public final class BusinessMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BusinessMO> {
        NSFetchRequest<BusinessMO>(entityName: "Business")
    }

    @NSManaged public var id: UUID
    @NSManaged public var legalName: String
    @NSManaged public var tradeName: String?
    @NSManaged public var startDate: Date
    @NSManaged public var baseCurrencyCode: String
    @NSManaged public var notes: String?
    @NSManaged public var scope: FinancialScopeMO?
}

@objc(UserProfileMO)
public final class UserProfileMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfileMO> {
        NSFetchRequest<UserProfileMO>(entityName: "UserProfile")
    }

    @NSManaged public var id: UUID
    @NSManaged public var displayName: String
    @NSManaged public var baseCurrencyCode: String
    @NSManaged public var calendarPreferenceRaw: String
    @NSManaged public var digitStyleRaw: String
    @NSManaged public var themePreferenceRaw: String
}
