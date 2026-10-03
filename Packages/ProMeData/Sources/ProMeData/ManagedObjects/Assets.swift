import CoreData
import Foundation
import ProMeDomain

@objc(AssetMO)
public final class AssetMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AssetMO> {
        NSFetchRequest<AssetMO>(entityName: "Asset")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var typeRaw: String
    @NSManaged public var purchasePriceMinor: Int64
    @NSManaged public var purchaseDate: Date
    @NSManaged public var currentValueMinor: Int64
    @NSManaged public var valuationDate: Date
    @NSManaged public var currencyCode: String
    @NSManaged public var statusRaw: String
    @NSManaged public var soldAt: Date?
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var valuations: Set<AssetValuationMO>
    @NSManaged public var journal: JournalMO?
    @NSManaged public var saleJournal: JournalMO?

    public var type: AssetType {
        get { AssetType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    public var status: AssetStatus {
        get { AssetStatus(rawValue: statusRaw) ?? .owned }
        set { statusRaw = newValue.rawValue }
    }

    public var bookValueMinor: Int64 {
        journal == nil ? currentValueMinor : 0
    }
}

@objc(AssetValuationMO)
public final class AssetValuationMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AssetValuationMO> {
        NSFetchRequest<AssetValuationMO>(entityName: "AssetValuation")
    }

    @NSManaged public var id: UUID
    @NSManaged public var valueMinor: Int64
    @NSManaged public var date: Date
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var asset: AssetMO?
}

@objc(ReconciliationMO)
public final class ReconciliationMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ReconciliationMO> {
        NSFetchRequest<ReconciliationMO>(entityName: "Reconciliation")
    }

    @NSManaged public var id: UUID
    @NSManaged public var asOfDate: Date
    @NSManaged public var bankBalanceMinor: Int64
    @NSManaged public var appBalanceMinor: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var account: MoneyAccountMO?

    public var differenceMinor: Int64 {
        bankBalanceMinor - appBalanceMinor
    }
}
