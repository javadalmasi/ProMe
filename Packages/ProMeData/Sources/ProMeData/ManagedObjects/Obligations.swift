import CoreData
import Foundation
import ProMeDomain

@objc(DebtMO)
public final class DebtMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DebtMO> {
        NSFetchRequest<DebtMO>(entityName: "Debt")
    }

    @NSManaged public var id: UUID
    @NSManaged public var directionRaw: String
    @NSManaged public var principalMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var date: Date
    @NSManaged public var dueDate: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var counterparty: CounterpartyMO?
    @NSManaged public var payments: Set<DebtPaymentMO>
    @NSManaged public var journal: JournalMO?

    public var direction: DebtKind {
        get { DebtKind(rawValue: directionRaw) ?? .receivable }
        set { directionRaw = newValue.rawValue }
    }

    public var status: DebtStatus {
        get { DebtStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    public var paidMinor: Int64 {
        payments.reduce(0) { $0 + $1.amountMinor }
    }

    public var remainingMinor: Int64 {
        max(0, principalMinor - paidMinor)
    }
}

@objc(DebtPaymentMO)
public final class DebtPaymentMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DebtPaymentMO> {
        NSFetchRequest<DebtPaymentMO>(entityName: "DebtPayment")
    }

    @NSManaged public var id: UUID
    @NSManaged public var amountMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var date: Date
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var debt: DebtMO?
    @NSManaged public var journal: JournalMO?
}

@objc(LoanMO)
public final class LoanMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LoanMO> {
        NSFetchRequest<LoanMO>(entityName: "Loan")
    }

    @NSManaged public var id: UUID
    @NSManaged public var lenderName: String
    @NSManaged public var principalMinor: Int64
    @NSManaged public var annualRate: NSDecimalNumber?
    @NSManaged public var termMonths: Int32
    @NSManaged public var startDate: Date
    @NSManaged public var dueDay: Int32
    @NSManaged public var currencyCode: String
    @NSManaged public var statusRaw: String
    @NSManaged public var memo: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var account: MoneyAccountMO?
    @NSManaged public var installments: Set<LoanInstallmentMO>
    @NSManaged public var journal: JournalMO?

    public var status: LoanStatus {
        get { LoanStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public var ratePercent: Decimal {
        get { annualRate?.decimalValue ?? 0 }
        set { annualRate = NSDecimalNumber(decimal: newValue) }
    }

    public var sortedInstallments: [LoanInstallmentMO] {
        installments.sorted { $0.index < $1.index }
    }

    public var paidInstallmentCount: Int {
        installments.filter { $0.status == .paid }.count
    }
}

@objc(LoanInstallmentMO)
public final class LoanInstallmentMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LoanInstallmentMO> {
        NSFetchRequest<LoanInstallmentMO>(entityName: "LoanInstallment")
    }

    @NSManaged public var id: UUID
    @NSManaged public var index: Int32
    @NSManaged public var dueDate: Date
    @NSManaged public var principalMinor: Int64
    @NSManaged public var interestMinor: Int64
    @NSManaged public var statusRaw: String
    @NSManaged public var paidAt: Date?
    @NSManaged public var loan: LoanMO?
    @NSManaged public var journal: JournalMO?

    public var status: InstallmentStatus {
        get { InstallmentStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var totalMinor: Int64 { principalMinor + interestMinor }

    public var isOverdue: Bool {
        status == .pending && dueDate < Date()
    }
}

@objc(InsuranceMO)
public final class InsuranceMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<InsuranceMO> {
        NSFetchRequest<InsuranceMO>(entityName: "Insurance")
    }

    @NSManaged public var id: UUID
    @NSManaged public var typeRaw: String
    @NSManaged public var organization: String
    @NSManaged public var policyNumber: String?
    @NSManaged public var contractNumber: String?
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date?
    @NSManaged public var premiumMinor: Int64
    @NSManaged public var currencyCode: String
    @NSManaged public var periodRaw: String
    @NSManaged public var statusRaw: String
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var scope: FinancialScopeMO?
    @NSManaged public var account: MoneyAccountMO?
    @NSManaged public var recurring: RecurringTransactionMO?

    public var type: InsuranceType {
        get { InsuranceType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    public var period: PaymentPeriod {
        get { PaymentPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    public var isActive: Bool {
        statusRaw == "active"
    }

    public func setActive(_ active: Bool) {
        statusRaw = active ? "active" : "expired"
    }
}
