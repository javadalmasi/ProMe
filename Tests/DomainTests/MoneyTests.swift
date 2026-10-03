import Foundation
import ProMeDomain
import Testing

@Suite("Money")
struct MoneyTests {
    @Test func addsSameCurrency() throws {
        let a = Money(minorUnits: 1_500_000, currency: .irr)
        let b = Money(minorUnits: 500_000, currency: .irr)
        #expect(try a.adding(b).minorUnits == 2_000_000)
    }

    @Test func subtracts() throws {
        let result = try Money(minorUnits: 1_000, currency: .usd).subtracting(Money(minorUnits: 250, currency: .usd))
        #expect(result.minorUnits == 750)
    }

    @Test func negates() throws {
        #expect(try Money(minorUnits: 42, currency: .irr).negated().minorUnits == -42)
        #expect(try Money(minorUnits: -42, currency: .irr).negated().minorUnits == 42)
    }

    @Test func detectsOverflow() {
        #expect(throws: AccountingError.amountOverflow.self) {
            try Money(minorUnits: Int64.max, currency: .irr).adding(Money(minorUnits: 1, currency: .irr))
        }
    }

    @Test func rejectsMismatchedCurrencies() {
        #expect(throws: AccountingError.self) {
            try Money(minorUnits: 1, currency: .irr).adding(Money(minorUnits: 1, currency: .usd))
        }
    }

    @Test func buildsFromMajorUnitsWithHalfUpRounding() throws {
        let halfUp = try #require(Decimal(string: "0.005"))
        #expect(Money(majorUnits: halfUp, currency: .usd).minorUnits == 1)

        let below = try #require(Decimal(string: "0.004"))
        #expect(Money(majorUnits: below, currency: .usd).minorUnits == 0)
    }

    @Test func convertsIRRToUSD() throws {
        let rials = Money(minorUnits: 1_000_000, currency: .irr)
        let rate = try #require(Decimal(string: "0.000001"))
        let dollars = try rials.converted(to: .usd, rate: rate)
        #expect(dollars.minorUnits == 100)
    }

    @Test func convertsUSDToIRR() throws {
        let cents = Money(minorUnits: 150, currency: .usd)
        let rials = try cents.converted(to: .irr, rate: 1_000_000)
        #expect(rials.minorUnits == 1_500_000)
    }

    @Test func rejectsInvalidRate() {
        #expect(throws: AccountingError.invalidExchangeRate.self) {
            try Money(minorUnits: 1, currency: .usd).converted(to: .irr, rate: 0)
        }
    }

    @Test func formatsGroupedIntegers() {
        #expect(Money(minorUnits: 1_500_000, currency: .irr).formatted() == "1,500,000 IRR")
    }

    @Test func formatsMinorUnitsAsMajor() {
        #expect(Money(minorUnits: 150, currency: .usd).formatted() == "1.50 USD")
    }
}
