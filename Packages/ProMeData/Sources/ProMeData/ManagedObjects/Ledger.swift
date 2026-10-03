import CoreData
import Foundation
import ProMeDomain

@objc(MoneyAccountMO)
public final class MoneyAccountMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MoneyAccountMO> {
        NSFetchRequest<MoneyAccountMO>(entityName: "MoneyAccount")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var bankName: String?
    @NSManaged public var accountNumber: String?
    @NSManaged public var cardNumber: String?
    @NSManaged public var iban: String?
    @NSManaged public var typeRaw: String
    @NSManaged public var currencyCode: String
    @NSManaged public var openingBalanceMinor: Int64
    @NSManaged public var openedAt: Date
    @NSManaged public var notes: String?
    @NSManaged public var statusRaw: String
    @NSManaged public var position: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var ledgerAccount: LedgerAccountMO?
    @NSManaged public var transactions: Set<TransactionMO>
    @NSManaged public var outgoingTransfers: Set<TransactionMO>
    @NSManaged public var incomingTransfers: Set<TransactionMO>
    @NSManaged public var recurringTransactions: Set<RecurringTransactionMO>
    @NSManaged public var loans: Set<LoanMO>
    @NSManaged public var insurances: Set<InsuranceMO>
    @NSManaged public var reconciliations: Set<ReconciliationMO>

    public var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    public var status: AccountStatus {
        get { AccountStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public var currency: Currency {
        Currency.resolving(currencyCode)
    }
}

@objc(LedgerAccountMO)
public final class LedgerAccountMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LedgerAccountMO> {
        NSFetchRequest<LedgerAccountMO>(entityName: "LedgerAccount")
    }

    @NSManaged public var id: UUID
    @NSManaged public var code: String
    @NSManaged public var name: String
    @NSManaged public var typeRaw: String
    @NSManaged public var normalSideRaw: String
    @NSManaged public var createdAt: Date
    @NSManaged public var moneyAccount: MoneyAccountMO?
    @NSManaged public var category: CategoryMO?
    @NSManaged public var lines: Set<LedgerLineMO>

    public var type: LedgerAccountType {
        get { LedgerAccountType(rawValue: typeRaw) ?? .asset }
        set { typeRaw = newValue.rawValue }
    }

    public var normalSide: LedgerDirection {
        get { LedgerDirection(rawValue: normalSideRaw) ?? .debit }
        set { normalSideRaw = newValue.rawValue }
    }
}

@objc(JournalMO)
public final class JournalMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<JournalMO> {
        NSFetchRequest<JournalMO>(entityName: "Journal")
    }

    @NSManaged public var id: UUID
    @NSManaged public var kindRaw: String
    @NSManaged public var date: Date
    @NSManaged public var memo: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var lines: Set<LedgerLineMO>
    @NSManaged public var transaction: TransactionMO?
    @NSManaged public var debt: DebtMO?
    @NSManaged public var debtPayment: DebtPaymentMO?
    @NSManaged public var loan: LoanMO?
    @NSManaged public var loanInstallment: LoanInstallmentMO?
    @NSManaged public var asset: AssetMO?
    @NSManaged public var assetSale: AssetMO?

    public var kind: JournalKind {
        get { JournalKind(rawValue: kindRaw) ?? .correction }
        set { kindRaw = newValue.rawValue }
    }
}

@objc(LedgerLineMO)
public final class LedgerLineMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LedgerLineMO> {
        NSFetchRequest<LedgerLineMO>(entityName: "LedgerLine")
    }

    @NSManaged public var id: UUID
    @NSManaged public var directionRaw: String
    @NSManaged public var amountMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var journal: JournalMO?
    @NSManaged public var ledgerAccount: LedgerAccountMO?

    public var direction: LedgerDirection {
        get { LedgerDirection(rawValue: directionRaw) ?? .debit }
        set { directionRaw = newValue.rawValue }
    }
}
