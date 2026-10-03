import Foundation
import ProMeDomain
import Testing

@Suite("Journal builder")
struct JournalBuilderTests {
    private func expenseLines(debit: Int64, credit: Int64) -> [PostingLine] {
        let categoryID = UUID()
        let accountID = UUID()
        return [
            PostingLine(
                ledgerAccountCode: ChartOfAccounts.expenseCategoryCode(forCategoryID: categoryID),
                direction: .debit,
                money: Money(minorUnits: debit, currency: .irr)
            ),
            PostingLine(
                ledgerAccountCode: ChartOfAccounts.assetAccountCode(forAccountID: accountID),
                direction: .credit,
                money: Money(minorUnits: credit, currency: .irr)
            ),
        ]
    }

    @Test func buildsBalancedJournal() throws {
        let journal = try JournalBuilder.build(
            kind: .expense,
            date: .now,
            memo: "Groceries",
            lines: expenseLines(debit: 10_000_000, credit: 10_000_000)
        )
        #expect(journal.lines.count == 2)
        #expect(journal.kind == .expense)
    }

    @Test func rejectsUnbalancedJournal() {
        #expect(throws: AccountingError.self) {
            try JournalBuilder.build(kind: .expense, date: .now, memo: nil, lines: expenseLines(debit: 10_000_000, credit: 9_000_000))
        }
    }

    @Test func rejectsSingleLine() {
        let lines = [expenseLines(debit: 1, credit: 1)[0]]
        #expect(throws: AccountingError.emptyJournal.self) {
            try JournalBuilder.build(kind: .adjustment, date: .now, memo: nil, lines: lines)
        }
    }

    @Test func rejectsMixedCurrencies() {
        let lines = [
            PostingLine(ledgerAccountCode: "AST.1", direction: .debit, money: Money(minorUnits: 1_500_000, currency: .irr)),
            PostingLine(ledgerAccountCode: "AST.2", direction: .credit, money: Money(minorUnits: 150, currency: .usd)),
        ]
        #expect(throws: AccountingError.mixedCurrencyJournal.self) {
            try JournalBuilder.build(kind: .currencyConversion, date: .now, memo: nil, lines: lines)
        }
    }

    @Test func incomeCreditsIncomeAndDebitsAsset() throws {
        let accountID = UUID()
        let categoryID = UUID()
        let journal = try JournalBuilder.build(
            kind: .income,
            date: .now,
            memo: nil,
            lines: [
                PostingLine(ledgerAccountCode: ChartOfAccounts.assetAccountCode(forAccountID: accountID), direction: .debit, money: Money(minorUnits: 5_000_000, currency: .irr)),
                PostingLine(ledgerAccountCode: ChartOfAccounts.incomeCategoryCode(forCategoryID: categoryID), direction: .credit, money: Money(minorUnits: 5_000_000, currency: .irr)),
            ]
        )
        let debitCodes = journal.lines.filter { $0.direction == .debit }.map(\.ledgerAccountCode)
        #expect(debitCodes == [ChartOfAccounts.assetAccountCode(forAccountID: accountID)])
    }
}
