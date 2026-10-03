import CoreData
import Foundation
import ProMeDomain

/// Accounts receivable / payable against counterparties. Lending money is
/// a receivable (asset), borrowing is a payable (liability) — neither is
/// income nor expense.
@MainActor
public final class DebtService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func all(direction: DebtKind, scope: FinancialScopeMO?) throws -> [DebtMO] {
        let request = DebtMO.fetchRequest()
        var clauses = [NSPredicate(format: "directionRaw == %@", direction.rawValue)]
        if let scope {
            clauses.append(NSPredicate(format: "scope == %@", scope))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true), NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    public struct NewDebt {
        public var direction: DebtKind
        public var counterpartyName: String
        public var principalMinor: Int64
        public var date: Date
        public var dueDate: Date?
        public var account: MoneyAccountMO
        public var notes: String?

        public init(
            direction: DebtKind,
            counterpartyName: String,
            principalMinor: Int64,
            date: Date = .now,
            dueDate: Date? = nil,
            account: MoneyAccountMO,
            notes: String? = nil
        ) {
            self.direction = direction
            self.counterpartyName = counterpartyName
            self.principalMinor = principalMinor
            self.date = date
            self.dueDate = dueDate
            self.account = account
            self.notes = notes
        }
    }

    /// Lending posts Dr Receivable / Cr account; borrowing posts
    /// Dr account / Cr Payable. The journal is kept on the debt so a
    /// deletion can reverse the books cleanly.
    public func create(_ draft: NewDebt, in scope: FinancialScopeMO) throws -> DebtMO {
        let name = draft.counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingField("counterparty") }
        guard draft.principalMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard draft.account.status == .active else { throw ValidationError.invalidState("The account is archived.") }

        let counterparty = try Self.ensureCounterparty(named: name, in: context)
        let debt = DebtMO(context: context)
        debt.id = UUID()
        debt.direction = draft.direction
        debt.principalMinor = draft.principalMinor
        debt.currencyCode = draft.account.currencyCode
        debt.date = draft.date
        debt.dueDate = draft.dueDate
        debt.status = .open
        debt.notes = draft.notes
        debt.createdAt = .now
        debt.scope = scope
        debt.counterparty = counterparty

        let money = Money(minorUnits: draft.principalMinor, currency: draft.account.currency)
        let lines: [PostingLine]
        let journalKind: JournalKind
        switch draft.direction {
        case .receivable:
            let receivable = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.receivableCode(forCounterpartyID: counterparty.id),
                name: "Receivable: \(name)",
                type: .asset,
                normalSide: .debit,
                in: context
            )
            lines = [
                PostingLine(ledgerAccountCode: receivable.code, direction: .debit, money: money),
                PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: draft.account, in: context).code, direction: .credit, money: money),
            ]
            journalKind = .debtLent
        case .payable:
            let payable = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.payableCode(forCounterpartyID: counterparty.id),
                name: "Payable: \(name)",
                type: .liability,
                normalSide: .credit,
                in: context
            )
            lines = [
                PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: draft.account, in: context).code, direction: .debit, money: money),
                PostingLine(ledgerAccountCode: payable.code, direction: .credit, money: money),
            ]
            journalKind = .debtBorrowed
        }
        let balanced = try JournalBuilder.build(kind: journalKind, date: draft.date, memo: name, lines: lines)
        debt.journal = try Self.attach(balanced, kind: journalKind, to: debt, in: context)
        try controller.saveViewContext()
        return debt
    }

    /// Settling a receivable brings money back: Dr account / Cr Receivable.
    /// Settling a payable pays it off: Dr Payable / Cr account.
    public func recordPayment(
        _ debt: DebtMO,
        account: MoneyAccountMO,
        amountMinor: Int64,
        date: Date,
        notes: String? = nil
    ) throws -> DebtPaymentMO {
        guard amountMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard amountMinor <= debt.remainingMinor else {
            throw ValidationError.invalidAmount("The payment exceeds the remaining balance.")
        }
        guard account.currencyCode == debt.currencyCode else {
            throw ValidationError.invalidState("The account currency must match the debt currency.")
        }

        let counterpartyID = debt.counterparty?.id ?? UUID()
        let money = Money(minorUnits: amountMinor, currency: account.currency)
        let lines: [PostingLine]
        let journalKind: JournalKind
        switch debt.direction {
        case .receivable:
            let receivable = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.receivableCode(forCounterpartyID: counterpartyID),
                name: "Receivable",
                type: .asset,
                normalSide: .debit,
                in: context
            )
            lines = [
                PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: account, in: context).code, direction: .debit, money: money),
                PostingLine(ledgerAccountCode: receivable.code, direction: .credit, money: money),
            ]
            journalKind = .debtRepaid
        case .payable:
            let payable = try AccountRepository.ensureLedgerAccount(
                code: ChartOfAccounts.payableCode(forCounterpartyID: counterpartyID),
                name: "Payable",
                type: .liability,
                normalSide: .credit,
                in: context
            )
            lines = [
                PostingLine(ledgerAccountCode: payable.code, direction: .debit, money: money),
                PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: account, in: context).code, direction: .credit, money: money),
            ]
            journalKind = .debtSettled
        }
        let balanced = try JournalBuilder.build(kind: journalKind, date: date, memo: debt.counterparty?.displayName, lines: lines)

        let payment = DebtPaymentMO(context: context)
        payment.id = UUID()
        payment.amountMinor = amountMinor
        payment.currencyCode = debt.currencyCode
        payment.date = date
        payment.notes = notes
        payment.createdAt = .now
        payment.debt = debt
        payment.journal = try Self.attach(balanced, kind: journalKind, to: payment, in: context)

        if debt.remainingMinor - amountMinor <= 0 {
            debt.status = .settled
        }
        try controller.saveViewContext()
        return payment
    }

    /// Deleting a debt removes its journal (and every payment journal),
    /// reversing the books exactly.
    public func delete(_ debt: DebtMO) throws {
        for payment in debt.payments {
            if let journal = payment.journal {
                context.delete(journal)
            }
        }
        if let journal = debt.journal {
            context.delete(journal)
        }
        context.delete(debt)
        try controller.saveViewContext()
    }

    // MARK: - Helpers

    static func ensureCounterparty(named name: String, in context: NSManagedObjectContext) throws -> CounterpartyMO {
        let request = CounterpartyMO.fetchRequest()
        request.predicate = NSPredicate(format: "displayName ==[cd] %@", name)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let counterparty = CounterpartyMO(context: context)
        counterparty.id = UUID()
        counterparty.displayName = name
        counterparty.kind = .person
        return counterparty
    }

    static func attach(
        _ balanced: BalancedJournal,
        kind: JournalKind,
        to debt: DebtMO,
        in context: NSManagedObjectContext
    ) throws -> JournalMO {
        try ObligationPosting.attach(balanced, kind: kind, in: context) { journal in
            journal.debt = debt
        }
    }

    static func attach(
        _ balanced: BalancedJournal,
        kind: JournalKind,
        to payment: DebtPaymentMO,
        in context: NSManagedObjectContext
    ) throws -> JournalMO {
        try ObligationPosting.attach(balanced, kind: kind, in: context) { journal in
            journal.debtPayment = payment
        }
    }
}

/// Loans: receiving money creates a liability; each installment pays the
/// principal part plus interest. Never revenue, never plain expense.
@MainActor
public final class LoanService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func all(scope: FinancialScopeMO?) throws -> [LoanMO] {
        let request = LoanMO.fetchRequest()
        if let scope {
            request.predicate = NSPredicate(format: "scope == %@", scope)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return try context.fetch(request)
    }

    public struct NewLoan {
        public var lenderName: String
        public var principalMinor: Int64
        public var annualRatePercent: Decimal
        public var termMonths: Int
        public var startDate: Date
        public var dueDay: Int
        public var account: MoneyAccountMO
        public var memo: String?

        public init(
            lenderName: String,
            principalMinor: Int64,
            annualRatePercent: Decimal = 0,
            termMonths: Int,
            startDate: Date = .now,
            dueDay: Int = 1,
            account: MoneyAccountMO,
            memo: String? = nil
        ) {
            self.lenderName = lenderName
            self.principalMinor = principalMinor
            self.annualRatePercent = annualRatePercent
            self.termMonths = termMonths
            self.startDate = startDate
            self.dueDay = dueDay
            self.account = account
            self.memo = memo
        }
    }

    /// Receiving the loan: Dr account / Cr Loan liability, and the
    /// installment schedule is generated up front.
    public func create(_ draft: NewLoan, in scope: FinancialScopeMO) throws -> LoanMO {
        let lender = draft.lenderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lender.isEmpty else { throw ValidationError.missingField("lender") }
        guard draft.principalMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }
        guard draft.termMonths >= 1 else { throw ValidationError.invalidAmount("The term must be at least one month.") }
        guard draft.account.status == .active else { throw ValidationError.invalidState("The account is archived.") }

        let loan = LoanMO(context: context)
        loan.id = UUID()
        loan.lenderName = lender
        loan.principalMinor = draft.principalMinor
        loan.ratePercent = draft.annualRatePercent
        loan.termMonths = Int32(draft.termMonths)
        loan.startDate = draft.startDate
        loan.dueDay = Int32(max(1, min(31, draft.dueDay)))
        loan.currencyCode = draft.account.currencyCode
        loan.status = .active
        loan.memo = draft.memo
        loan.createdAt = .now
        loan.scope = scope
        loan.account = draft.account

        let calendar = Calendar.current
        let plans = LoanMath.schedule(
            principalMinor: draft.principalMinor,
            annualRatePercent: draft.annualRatePercent,
            termMonths: draft.termMonths,
            startDate: draft.startDate,
            dueDay: Int(loan.dueDay),
            calendar: calendar
        )
        for plan in plans {
            let installment = LoanInstallmentMO(context: context)
            installment.id = UUID()
            installment.index = Int32(plan.index)
            installment.dueDate = plan.dueDate
            installment.principalMinor = plan.principalMinor
            installment.interestMinor = plan.interestMinor
            installment.status = .pending
            installment.loan = loan
        }

        let liability = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.loanLiabilityCode(forLoanID: loan.id),
            name: "Loan: \(lender)",
            type: .liability,
            normalSide: .credit,
            in: context
        )
        let money = Money(minorUnits: draft.principalMinor, currency: draft.account.currency)
        let balanced = try JournalBuilder.build(kind: .loanReceived, date: draft.startDate, memo: lender, lines: [
            PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: draft.account, in: context).code, direction: .debit, money: money),
            PostingLine(ledgerAccountCode: liability.code, direction: .credit, money: money),
        ])
        loan.journal = try ObligationPosting.attach(balanced, kind: .loanReceived, in: context) { journal in
            journal.loan = loan
        }
        try controller.saveViewContext()
        return loan
    }

    /// Remaining principal straight from the liability ledger.
    public func remainingPrincipal(_ loan: LoanMO) throws -> Int64 {
        let liability = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.loanLiabilityCode(forLoanID: loan.id),
            name: "Loan",
            type: .liability,
            normalSide: .credit,
            in: context
        )
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LedgerLine")
        request.predicate = NSPredicate(format: "ledgerAccount == %@", liability)
        let rows = try AggregateQueries.groupedRows(from: request, context: context, fetch: ["directionRaw"], sum: "amountMinor")
        var credit: Int64 = 0
        var debit: Int64 = 0
        for row in rows {
            let total = (row["total"] as? NSNumber)?.int64Value ?? 0
            if row["directionRaw"] as? String == LedgerDirection.credit.rawValue {
                credit += total
            } else {
                debit += total
            }
        }
        return credit - debit
    }

    /// Paying an installment: Dr Loan liability (principal),
    /// Dr Interest Expense, Cr account (principal + interest).
    public func pay(_ installment: LoanInstallmentMO, date: Date = .now) throws {
        guard installment.status == .pending else {
            throw ValidationError.invalidState("This installment is already paid.")
        }
        guard let loan = installment.loan, let account = loan.account else {
            throw ValidationError.invalidState("The loan has no payout account.")
        }
        let liability = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.loanLiabilityCode(forLoanID: loan.id),
            name: "Loan",
            type: .liability,
            normalSide: .credit,
            in: context
        )
        let interestLedger = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.interestExpenseCode,
            name: "Loan Interest",
            type: .expense,
            normalSide: .debit,
            in: context
        )
        let principal = Money(minorUnits: installment.principalMinor, currency: account.currency)
        let interest = Money(minorUnits: installment.interestMinor, currency: account.currency)
        let total = try principal.adding(interest)
        let balanced = try JournalBuilder.build(kind: .loanInstallment, date: date, memo: loan.lenderName, lines: [
            PostingLine(ledgerAccountCode: liability.code, direction: .debit, money: principal),
            PostingLine(ledgerAccountCode: interestLedger.code, direction: .debit, money: interest),
            PostingLine(ledgerAccountCode: try AccountRepository.ensureAssetLedger(for: account, in: context).code, direction: .credit, money: total),
        ])

        installment.journal = try ObligationPosting.attach(balanced, kind: .loanInstallment, in: context) { journal in
            journal.loanInstallment = installment
        }
        installment.status = .paid
        installment.paidAt = date

        if loan.installments.allSatisfy({ $0.status == .paid }) {
            loan.status = .settled
        }
        try controller.saveViewContext()
    }

    public func nextPendingInstallment(_ loan: LoanMO) -> LoanInstallmentMO? {
        loan.sortedInstallments.first { $0.status == .pending }
    }

    public func delete(_ loan: LoanMO) throws {
        for installment in loan.installments {
            if let journal = installment.journal {
                context.delete(journal)
            }
        }
        if let journal = loan.journal {
            context.delete(journal)
        }
        context.delete(loan)
        try controller.saveViewContext()
    }
}

/// Insurance policies with optional auto-created premium recurrence.
@MainActor
public final class InsuranceService {
    private let controller: PersistenceController
    private let recurring: RecurringService
    public init(controller: PersistenceController, recurring: RecurringService) {
        self.controller = controller
        self.recurring = recurring
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func all(scope: FinancialScopeMO?) throws -> [InsuranceMO] {
        let request = InsuranceMO.fetchRequest()
        if let scope {
            request.predicate = NSPredicate(format: "scope == %@", scope)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return try context.fetch(request)
    }

    public struct NewInsurance {
        public var type: InsuranceType
        public var organization: String
        public var policyNumber: String?
        public var contractNumber: String?
        public var startDate: Date
        public var endDate: Date?
        public var premiumMinor: Int64
        public var period: PaymentPeriod
        public var account: MoneyAccountMO
        public var createRecurring: Bool
        public var notes: String?

        public init(
            type: InsuranceType = .supplementary,
            organization: String,
            policyNumber: String? = nil,
            contractNumber: String? = nil,
            startDate: Date = .now,
            endDate: Date? = nil,
            premiumMinor: Int64,
            period: PaymentPeriod = .monthly,
            account: MoneyAccountMO,
            createRecurring: Bool = true,
            notes: String? = nil
        ) {
            self.type = type
            self.organization = organization
            self.policyNumber = policyNumber
            self.contractNumber = contractNumber
            self.startDate = startDate
            self.endDate = endDate
            self.premiumMinor = premiumMinor
            self.period = period
            self.account = account
            self.createRecurring = createRecurring
            self.notes = notes
        }
    }

    public func create(_ draft: NewInsurance, in scope: FinancialScopeMO) throws -> InsuranceMO {
        let org = draft.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !org.isEmpty else { throw ValidationError.missingField("organization") }
        guard draft.premiumMinor > 0 else { throw ValidationError.invalidAmount("Amounts must be greater than zero.") }

        let insurance = InsuranceMO(context: context)
        insurance.id = UUID()
        insurance.type = draft.type
        insurance.organization = org
        insurance.policyNumber = draft.policyNumber
        insurance.contractNumber = draft.contractNumber
        insurance.startDate = draft.startDate
        insurance.endDate = draft.endDate
        insurance.premiumMinor = draft.premiumMinor
        insurance.currencyCode = draft.account.currencyCode
        insurance.period = draft.period
        insurance.setActive(true)
        insurance.notes = draft.notes
        insurance.createdAt = .now
        insurance.scope = scope
        insurance.account = draft.account

        if draft.createRecurring {
            let category = try Self.ensureInsuranceCategory(in: context)
            let recurringDraft = RecurringService.Draft(
                kind: .expense,
                amountMinor: draft.premiumMinor,
                account: draft.account,
                category: category,
                frequency: draft.period == .monthly ? .monthly : (draft.period == .quarterly ? .quarterly : .yearly),
                interval: 1,
                startDate: draft.startDate,
                endDate: draft.endDate,
                autoPost: true,
                memo: "Insurance: \(org)"
            )
            let recurring = try recurring.create(recurringDraft, in: scope)
            insurance.recurring = recurring
        }
        try controller.saveViewContext()
        return insurance
    }

    /// Expires the policy and stops its premium recurrence.
    public func cancel(_ insurance: InsuranceMO) throws {
        insurance.setActive(false)
        if let premiumRecurring = insurance.recurring {
            try self.recurring.cancel(premiumRecurring)
        }
        try controller.saveViewContext()
    }

    public func delete(_ insurance: InsuranceMO) throws {
        if let premiumRecurring = insurance.recurring {
            try self.recurring.cancel(premiumRecurring)
        }
        context.delete(insurance)
        try controller.saveViewContext()
    }

    /// The seeded "بیمه" expense category, or a fresh one.
    static func ensureInsuranceCategory(in context: NSManagedObjectContext) throws -> CategoryMO {
        let request = CategoryMO.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@ AND kindRaw == %@", "بیمه", CategoryKind.expense.rawValue)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let category = CategoryMO(context: context)
        category.id = UUID()
        category.name = "بیمه"
        category.kind = .expense
        category.isSystem = true
        category.createdAt = .now
        category.ledgerAccount = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.expenseCategoryCode(forCategoryID: category.id),
            name: "بیمه",
            type: .expense,
            normalSide: .debit,
            in: context
        )
        return category
    }
}

/// Shared journal-attachment helper for obligation services.
@MainActor
enum ObligationPosting {
    static func attach(
        _ balanced: BalancedJournal,
        kind: JournalKind,
        in context: NSManagedObjectContext,
        link: (JournalMO) -> Void
    ) throws -> JournalMO {
        let journal = JournalMO(context: context)
        journal.id = UUID()
        journal.kind = kind
        journal.date = balanced.date
        journal.createdAt = .now
        journal.memo = balanced.memo
        link(journal)

        var ledgersByCode: [String: LedgerAccountMO] = [:]
        for line in balanced.lines {
            let ledger: LedgerAccountMO
            if let cached = ledgersByCode[line.ledgerAccountCode] {
                ledger = cached
            } else {
                let request = LedgerAccountMO.fetchRequest()
                request.predicate = NSPredicate(format: "code == %@", line.ledgerAccountCode)
                request.fetchLimit = 1
                guard let found = try context.fetch(request).first else {
                    throw AccountingError.unknownLedgerAccount(code: line.ledgerAccountCode)
                }
                ledgersByCode[line.ledgerAccountCode] = found
                ledger = found
            }
            let row = LedgerLineMO(context: context)
            row.id = UUID()
            row.direction = line.direction
            row.amountMinor = line.money.minorUnits
            row.currencyCode = line.money.currency.code
            row.journal = journal
            row.ledgerAccount = ledger
        }
        return journal
    }
}
