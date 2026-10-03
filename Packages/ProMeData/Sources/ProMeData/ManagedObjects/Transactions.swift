import CoreData
import Foundation
import ProMeDomain

@objc(TransactionMO)
public final class TransactionMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionMO> {
        NSFetchRequest<TransactionMO>(entityName: "Transaction")
    }

    @NSManaged public var id: UUID
    @NSManaged public var kindRaw: String
    @NSManaged public var postedAt: Date
    @NSManaged public var dateKey: Int32
    @NSManaged public var amountMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var memo: String?
    @NSManaged public var notes: String?
    @NSManaged public var referenceNo: String?
    @NSManaged public var isReconciled: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var account: MoneyAccountMO?
    @NSManaged public var fromAccount: MoneyAccountMO?
    @NSManaged public var toAccount: MoneyAccountMO?
    @NSManaged public var category: CategoryMO?
    @NSManaged public var counterparty: CounterpartyMO?
    @NSManaged public var tags: Set<TagMO>
    @NSManaged public var attachments: Set<AttachmentMO>
    @NSManaged public var journal: JournalMO?

    public var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    public var currency: Currency {
        Currency.resolving(currencyCode)
    }
}

@objc(AttachmentMO)
public final class AttachmentMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AttachmentMO> {
        NSFetchRequest<AttachmentMO>(entityName: "Attachment")
    }

    @NSManaged public var id: UUID
    @NSManaged public var fileName: String
    @NSManaged public var relativePath: String
    @NSManaged public var kindRaw: String
    @NSManaged public var sizeBytes: Int64
    @NSManaged public var checksum: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var transaction: TransactionMO?

    public var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}
