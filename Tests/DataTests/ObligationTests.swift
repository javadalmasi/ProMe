import CoreData
import Foundation
import ProMeData
import ProMeDomain
import Testing

/// M6 scenarios: lending/borrowing, the full loan lifecycle with
/// installments, and insurance with an auto-created premium recurrence.
@Suite("Obligations: debts, loans, insurance")
@MainActor
struct ObligationTests {
    struct World {
        let controller: PersistenceController
        let scopes: ScopeRepository
        let accounts: AccountRepository
        let categories: CategoryRepository
        let posting: PostingService
        let aggregates: AggregateQueries
        let recurring: RecurringService
        let debts: DebtService
        let loans: LoanService
        let insurances: InsuranceService
        let personal: FinancialScopeMO
        let bank: MoneyAccountMO
    }

    private func makeWorld() throws -> World {
        let controller = try PersistenceController(inMemory: true)
        let scopes = ScopeRepository(controller: controller)
        let accounts = AccountRepository(controller: controller)
        let categories = CategoryRepository(controller: controller)
        let posting = PostingService(controller: controller)
        let aggregates = AggregateQueries(controller: controller)
        let recurring = RecurringService(controller: controller, posting: posting)
        let personal = try scopes.ensurePersonalScope()
        let bank = try accounts.create(AccountRepository.Draft(name: "Bank A", openingBalanceMinor: 10_000_000), in: personal)
        return World(
            controller: controller, scopes: scopes, accounts: accounts, categories: categories,
            posting: posting, aggregates: aggregates, recurring: recurring,
            debts: DebtService(controller: controller),
            loans: LoanService(controller: controller),
            insurances: InsuranceService(controller: controller, recurring: recurring),
            personal: personal, bank: bank
        )
    }

    private func balance(_ world: World, _ account: MoneyAccountMO) -> Int64 {
        (try? world.aggregates.accountBalance(account)) ?? -1
    }

    @Test("Scenario: lending 10,000,000 then receiving 3,000,000 back")
    func lendAndRepay() throws {
        let world = try makeWorld()
        let debt = try world.debts.create(
            DebtService.NewDebt(
                direction: .receivable, counterpartyName: "Ali",
                principalMinor: 10_000_000, account: world.bank
            ),
            in: world.personal
        )
        #expect(balance(world, world.bank) == 0)  // 10M opening − 10M lent
        #expect(debt.remainingMinor == 10_000_000)

        _ = try world.debts.recordPayment(debt, account: world.bank, amountMinor: 3_000_000, date: .now)
        #expect(balance(world, world.bank) == 3_000_000)
        #expect(debt.remainingMinor == 7_000_000)
        #expect(debt.status == .open)

        _ = try world.debts.recordPayment(debt, account: world.bank, amountMinor: 7_000_000, date: .now)
        #expect(debt.status == .settled)
        #expect(balance(world, world.bank) == 10_000_000)

        // Overpayment is refused.
        #expect(throws: ValidationError.self) {
            try world.debts.recordPayment(debt, account: world.bank, amountMinor: 1, date: .now)
        }
    }

    @Test("Scenario: borrowing 5,000,000 creates a payable, not income")
    func borrowCreatesPayable() throws {
        let world = try makeWorld()
        let debt = try world.debts.create(
            DebtService.NewDebt(
                direction: .payable, counterpartyName: "Sara",
                principalMinor: 5_000_000, account: world.bank
            ),
            in: world.personal
        )
        #expect(balance(world, world.bank) == 15_000_000)
        let income = try world.aggregates.sum(kind: .income, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(income.isEmpty)

        _ = try world.debts.recordPayment(debt, account: world.bank, amountMinor: 5_000_000, date: .now)
        #expect(balance(world, world.bank) == 10_000_000)
        #expect(debt.status == .settled)
    }

    @Test("Loan lifecycle: receive 50,000,000 at 12%, pay all 12 installments")
    func loanLifecycle() throws {
        let world = try makeWorld()
        let principal = 50_000_000
        let loan = try world.loans.create(
            LoanService.NewLoan(
                lenderName: "Bank Melli",
                principalMinor: Int64(principal),
                annualRatePercent: 12,
                termMonths: 12,
                startDate: Date(timeIntervalSince1970: 1_770_000_000),
                dueDay: 10,
                account: world.bank
            ),
            in: world.personal
        )
        #expect(loan.installments.count == 12)
        #expect(balance(world, world.bank) == 10_000_000 + principal)

        // Schedule sums: principal parts always total the principal.
        let principalSum = loan.installments.reduce(Int64(0)) { $0 + $1.principalMinor }
        #expect(principalSum == Int64(principal))
        let interestSum = loan.installments.reduce(Int64(0)) { $0 + $1.interestMinor }
        #expect(interestSum == 6_000_000)  // 12% flat over 12 months

        // Pay every installment.
        for installment in loan.sortedInstallments {
            try world.loans.pay(installment)
        }
        #expect(loan.status == .settled)
        let remaining = try world.loans.remainingPrincipal(loan)
        #expect(remaining == 0)

        // Interest lives on the EXP.INT ledger account (installments are
        // not plain transactions, so the transaction sums stay empty).
        let interestLedger = try AccountRepository.ensureLedgerAccount(
            code: ChartOfAccounts.interestExpenseCode,
            name: "Loan Interest",
            type: .expense,
            normalSide: .debit,
            in: world.controller.container.viewContext
        )
        let interest = try world.aggregates.ledgerBalance(interestLedger)
        #expect(interest == 6_000_000)
        #expect(balance(world, world.bank) == 10_000_000 - 6_000_000)

        // Double payment is refused.
        #expect(throws: ValidationError.self) {
            try world.loans.pay(loan.sortedInstallments[0])
        }
    }

    @Test("Loan schedule clamps month-end due dates")
    func scheduleClampsMonthEnd() {
        // A fixed Gregorian calendar: Calendar.current may be Persian.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let start = gregorian.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!
        let plans = LoanMath.schedule(
            principalMinor: 12_000, annualRatePercent: 0, termMonths: 3,
            startDate: start, dueDay: 31, calendar: gregorian
        )
        #expect(plans.count == 3)
        // Installment i falls i months after the start: Feb 28, Mar 31, Apr 30.
        #expect(gregorian.component(.month, from: plans[0].dueDate) == 2)
        #expect(gregorian.component(.day, from: plans[0].dueDate) == 28)
        #expect(gregorian.component(.month, from: plans[1].dueDate) == 3)
        #expect(gregorian.component(.day, from: plans[1].dueDate) == 31)
        #expect(gregorian.component(.month, from: plans[2].dueDate) == 4)
        #expect(gregorian.component(.day, from: plans[2].dueDate) == 30)
        let principalSum = plans.reduce(Int64(0)) { $0 + $1.principalMinor }
        #expect(principalSum == 12_000)
    }

    @Test("Insurance creation wires an auto premium recurrence")
    func insuranceCreatesRecurring() throws {
        let world = try makeWorld()
        let insurance = try world.insurances.create(
            InsuranceService.NewInsurance(
                type: .supplementary,
                organization: "Asia Insurance",
                premiumMinor: 5_000_000,
                period: .monthly,
                account: world.bank,
                createRecurring: true
            ),
            in: world.personal
        )
        #expect(insurance.isActive)
        let recurring = try #require(insurance.recurring)
        #expect(recurring.amountMinor == 5_000_000)
        #expect(recurring.autoPost)
        #expect(recurring.category?.name == "بیمه")

        // Posting due premiums creates an insurance expense.
        _ = try world.recurring.postDue(asOf: recurring.startDate.addingTimeInterval(1))
        let expense = try world.aggregates.sumByCategory(kind: .expense, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(expense.contains { $0.categoryName == "بیمه" })

        // Cancelling the policy stops the recurrence.
        try world.insurances.cancel(insurance)
        #expect(!insurance.isActive)
        #expect(insurance.recurring?.isActive == false)
    }
}
