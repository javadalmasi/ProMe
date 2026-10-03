import CoreData
import Foundation
import ProMeData
import ProMeDomain
import Testing

/// End-to-end service tests: posting rules, balances, transfers, owner
/// transfers, recurring catch-up and budget actuals — all on an in-memory
/// store, mirroring the scenarios from the product spec.
@Suite("Posting & services")
@MainActor
struct PostingServiceTests {
    struct World {
        let controller: PersistenceController
        let scopes: ScopeRepository
        let accounts: AccountRepository
        let categories: CategoryRepository
        let posting: PostingService
        let aggregates: AggregateQueries
        let recurring: RecurringService
        let budgets: BudgetService
        let personal: FinancialScopeMO
        let bank: MoneyAccountMO
        let cash: MoneyAccountMO
        let food: CategoryMO
        let salary: CategoryMO
    }

    private func makeWorld() throws -> World {
        let controller = try PersistenceController(inMemory: true)
        let scopes = ScopeRepository(controller: controller)
        let accounts = AccountRepository(controller: controller)
        let categories = CategoryRepository(controller: controller)
        let posting = PostingService(controller: controller)
        let aggregates = AggregateQueries(controller: controller)
        let recurring = RecurringService(controller: controller, posting: posting)
        let budgets = BudgetService(controller: controller, aggregates: aggregates)

        let personal = try scopes.ensurePersonalScope()
        let bank = try accounts.create(AccountRepository.Draft(name: "Bank A", openingBalanceMinor: 10_000_000), in: personal)
        let cash = try accounts.create(AccountRepository.Draft(name: "Wallet", type: .cash), in: personal)
        let food = try categories.create(name: "Food", kind: .expense, parent: nil)
        let salary = try categories.create(name: "Salary", kind: .income, parent: nil)

        return World(
            controller: controller, scopes: scopes, accounts: accounts, categories: categories,
            posting: posting, aggregates: aggregates, recurring: recurring, budgets: budgets,
            personal: personal, bank: bank, cash: cash, food: food, salary: salary
        )
    }

    private func balance(_ world: World, _ account: MoneyAccountMO) -> Int64 {
        (try? world.aggregates.accountBalance(account)) ?? -1
    }

    @Test("Scenario: paying 500,000 for food from the bank reduces its balance")
    func expenseReducesBalance() throws {
        let world = try makeWorld()
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 500_000, date: .now, memo: "Groceries"
        )
        #expect(balance(world, world.bank) == 9_500_000)
        let spend = try world.aggregates.sumByCategory(kind: .expense, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(spend.first?.minor == 500_000)
        #expect(spend.first?.categoryName == "Food")
    }

    @Test("Scenario: business income raises the account and shows as income, not expense")
    func incomeRaisesBalance() throws {
        let world = try makeWorld()
        _ = try world.posting.postIncome(
            scope: world.personal, account: world.bank, category: world.salary,
            amountMinor: 20_000_000, date: .now, memo: "Payday"
        )
        #expect(balance(world, world.bank) == 30_000_000)
        let income = try world.aggregates.sum(kind: .income, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(income.first?.minor == 20_000_000)
        let expense = try world.aggregates.sum(kind: .expense, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(expense.isEmpty)
    }

    @Test("Scenario: transferring 2,000,000 moves money and never touches income or expense")
    func transferMovesMoneyOnly() throws {
        let world = try makeWorld()
        _ = try world.posting.postTransfer(
            from: world.bank, to: world.cash, amountMinor: 2_000_000, date: .now, memo: "Pocket cash"
        )
        #expect(balance(world, world.bank) == 8_000_000)
        #expect(balance(world, world.cash) == 2_000_000)
        let income = try world.aggregates.sum(kind: .income, scope: world.personal, from: .distantPast, to: .distantFuture)
        let expense = try world.aggregates.sum(kind: .expense, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(income.isEmpty)
        #expect(expense.isEmpty)
    }

    @Test("Deleting a transaction restores the previous balance")
    func deleteRestoresBalance() throws {
        let world = try makeWorld()
        let transaction = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 1_000_000, date: .now, memo: nil
        )
        #expect(balance(world, world.bank) == 9_000_000)
        try world.posting.delete(transaction)
        #expect(balance(world, world.bank) == 10_000_000)
    }

    @Test("Scenario: 30,000,000 personal funding of a business is owner contribution, not revenue")
    func ownerContribution() throws {
        let world = try makeWorld()
        let business = try world.scopes.createBusiness(name: "Kalands", tradeName: nil, startDate: .now, baseCurrency: .irr)
        let businessAccount = try world.accounts.create(AccountRepository.Draft(name: "Biz Account"), in: business)
        _ = try world.posting.postOwnerContribution(
            from: world.bank, to: businessAccount, amountMinor: 30_000_000, date: .now, memo: "Seed money"
        )
        #expect(balance(world, world.bank) == 10_000_000 - 30_000_000)
        #expect(balance(world, businessAccount) == 30_000_000)

        let income = try world.aggregates.sum(kind: .income, scope: business, from: .distantPast, to: .distantFuture)
        #expect(income.isEmpty)
        let expense = try world.aggregates.sum(kind: .expense, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(expense.isEmpty)
    }

    @Test("Unbalanced or invalid postings are rejected")
    func validationGuards() throws {
        let world = try makeWorld()
        #expect(throws: ValidationError.self) {
            try world.posting.postExpense(
                scope: world.personal, account: world.bank, category: world.food,
                amountMinor: 0, date: .now, memo: nil
            )
        }
        #expect(throws: ValidationError.self) {
            try world.posting.postExpense(
                scope: world.personal, account: world.bank, category: world.salary,
                amountMinor: 1_000, date: .now, memo: nil
            )
        }
        #expect(throws: ValidationError.self) {
            try world.posting.postTransfer(
                from: world.bank, to: world.bank, amountMinor: 1_000, date: .now, memo: nil
            )
        }
    }

    @Test("Recurring catch-up posts every missed occurrence once")
    func recurringCatchUp() throws {
        let world = try makeWorld()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -2, to: .now)!
        let draft = RecurringService.Draft(
            kind: .expense, amountMinor: 100_000, account: world.bank, category: world.food,
            frequency: .monthly, interval: 1, startDate: start, endDate: nil, autoPost: true, memo: "Insurance"
        )
        let recurring = try world.recurring.create(draft, in: world.personal)
        let posted = try world.recurring.postDue(asOf: .now)
        #expect(posted.count == 3)
        #expect(recurring.nextDueAt > .now)
        #expect(balance(world, world.bank) == 10_000_000 - 300_000)
        // Running it again must not double-post.
        let again = try world.recurring.postDue(asOf: .now)
        #expect(again.isEmpty)
    }

    @Test("Budget rows roll up subcategory spending into the parent budget")
    func budgetRollsUpChildren() throws {
        let world = try makeWorld()
        let restaurant = try world.categories.create(name: "Restaurant", kind: .expense, parent: world.food)
        let monthKey = BudgetService.monthKey(for: .now, preference: .gregorian)
        try world.budgets.setBudget(category: world.food, scope: world.personal, monthKey: monthKey, amountMinor: 1_000_000, currency: .irr)
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: restaurant,
            amountMinor: 400_000, date: .now, memo: "Lunch"
        )
        let rows = try world.budgets.rows(monthKey: monthKey, scope: world.personal, from: .distantPast, to: .distantFuture)
        #expect(rows.count == 1)
        #expect(rows[0].spentMinor == 400_000)
        #expect(rows[0].fractionUsed == 0.4)
    }

    @Test("Transaction query filters by text, kind and period")
    func queryFilters() throws {
        let world = try makeWorld()
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 300_000, date: .now, memo: "Snapp ride"
        )
        _ = try world.posting.postIncome(
            scope: world.personal, account: world.bank, category: world.salary,
            amountMinor: 5_000_000, date: .now, memo: "Payday"
        )

        let repository = TransactionRepository(controller: world.controller)
        let text = try repository.fetch(TransactionQuery(text: "Snapp"))
        #expect(text.count == 1)
        let incomes = try repository.fetch(TransactionQuery(kinds: [.income]))
        #expect(incomes.count == 1)
        let future = try repository.fetch(TransactionQuery(startDate: .now.addingTimeInterval(86_400), endDate: .distantFuture))
        #expect(future.isEmpty)
    }
}
