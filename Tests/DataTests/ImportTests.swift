import CoreData
import Foundation
import ProMeData
import ProMeDomain
import Testing

/// M8 scenarios: CSV parsing/mapping, duplicate flagging, import posting,
/// and history-based category suggestions.
@Suite("CSV import & smart categorization")
@MainActor
struct ImportTests {
    struct World {
        let controller: PersistenceController
        let scopes: ScopeRepository
        let accounts: AccountRepository
        let categories: CategoryRepository
        let posting: PostingService
        let aggregates: AggregateQueries
        let importService: ImportService
        let categorization: CategorizationService
        let personal: FinancialScopeMO
        let bank: MoneyAccountMO
        let food: CategoryMO
        let salary: CategoryMO
    }

    private func makeWorld() throws -> World {
        let controller = try PersistenceController(inMemory: true)
        let scopes = ScopeRepository(controller: controller)
        let accounts = AccountRepository(controller: controller)
        let categories = CategoryRepository(controller: controller)
        let posting = PostingService(controller: controller)
        let personal = try scopes.ensurePersonalScope()
        let bank = try accounts.create(AccountRepository.Draft(name: "Bank A", openingBalanceMinor: 10_000_000), in: personal)
        let food = try categories.create(name: "Food", kind: .expense, parent: nil)
        let salary = try categories.create(name: "Salary", kind: .income, parent: nil)
        return World(
            controller: controller, scopes: scopes, accounts: accounts, categories: categories,
            posting: posting, aggregates: AggregateQueries(controller: controller),
            importService: ImportService(controller: controller, posting: posting),
            categorization: CategorizationService(controller: controller),
            personal: personal, bank: bank, food: food, salary: salary
        )
    }

    private let csv = """
    Date,Description,Debit,Credit,Ref
    2026-09-01,Snapp ride,150000,,R-100
    2026-09-02,Salary deposit,,20000000,R-101
    2026-09-03,Supermarket,750000,,R-102
    """

    @Test("CSV parser handles quotes, commas and CRLF")
    func parserBasics() {
        let parsed = CSVParser.parse("a,\"b,c\",\"x\"\"y\"\r\nd,e,f\n")
        #expect(parsed.count == 2)
        #expect(parsed[0] == ["a", "b,c", "x\"y"])
        #expect(parsed[1] == ["d", "e", "f"])
    }

    @Test("Debit/credit mapping produces signed drafts and flags duplicates")
    func draftsAndDuplicates() throws {
        let world = try makeWorld()
        // Seed an existing transaction that matches row 1.
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 150_000, date: ImportService.parseDate("2026-09-01")!, memo: "Snapp ride"
        )

        let cells = CSVParser.parse(csv)
        let mapping = ImportService.Mapping(
            dateColumn: 0, descriptionColumn: 1,
            amountColumn: nil, debitColumn: 2, creditColumn: 3,
            referenceColumn: 4, hasHeader: true
        )
        var drafts = try world.importService.draftRows(cells: cells, mapping: mapping, currency: .irr)
        #expect(drafts.count == 3)
        #expect(drafts[0].amountMinor == -150_000)
        #expect(drafts[1].amountMinor == 20_000_000)
        #expect(drafts[1].memo == "Salary deposit")

        try world.importService.flagDuplicates(account: world.bank, drafts: &drafts)
        #expect(drafts[0].isDuplicate)
        #expect(!drafts[1].isDuplicate)
        #expect(!drafts[2].isDuplicate)
    }

    @Test("Import posts through the ledger and respects the duplicate policy")
    func importPosts() throws {
        let world = try makeWorld()
        // Row 1 of the CSV already exists as a transaction.
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 150_000, date: ImportService.parseDate("2026-09-01")!, memo: "Snapp ride"
        )
        let cells = CSVParser.parse(csv)
        let mapping = ImportService.Mapping(
            dateColumn: 0, descriptionColumn: 1,
            amountColumn: nil, debitColumn: 2, creditColumn: 3,
            referenceColumn: 4, hasHeader: true
        )
        var drafts = try world.importService.draftRows(cells: cells, mapping: mapping, currency: .irr)
        try world.importService.flagDuplicates(account: world.bank, drafts: &drafts)

        let result = try world.importService.import(
            drafts: drafts, scope: world.personal, account: world.bank,
            incomeCategory: world.salary, expenseCategory: world.food,
            skipDuplicates: true
        )
        #expect(result.imported == 2)
        #expect(result.skippedDuplicates == 1)

        // Opening 10M − 150k (seeded) − 750k (food) + 20M (salary) = 29,100,000
        let balance = try world.aggregates.accountBalance(world.bank)
        #expect(balance == 29_100_000)

        // Same import without skipping would post 3 rows.
        let again = try world.importService.import(
            drafts: drafts, scope: world.personal, account: world.bank,
            incomeCategory: world.salary, expenseCategory: world.food,
            skipDuplicates: false
        )
        #expect(again.imported == 3)
    }

    @Test("Category suggestion learns from repeated descriptions")
    func categorySuggestion() throws {
        let world = try makeWorld()
        // Two past "Snapp" expenses in the taxi-ish category.
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 150_000, date: .now, memo: "Snapp ride"
        )
        _ = try world.posting.postExpense(
            scope: world.personal, account: world.bank, category: world.food,
            amountMinor: 180_000, date: .now, memo: "Snapp to work"
        )
        let suggestion = try world.categorization.suggestCategory(kind: .expense, memo: "Snapp 4000")
        #expect(suggestion?.id == world.food.id)

        // A single match is not a confident suggestion.
        _ = try world.posting.postIncome(
            scope: world.personal, account: world.bank, category: world.salary,
            amountMinor: 1_000_000, date: .now, memo: "Unique consulting"
        )
        let none = try world.categorization.suggestCategory(kind: .income, memo: "Unique consulting invoice")
        #expect(none == nil)
    }
}
