import Foundation

/// Exact monetary amount: an integer number of minor units plus a currency.
/// Money is never represented with floating point anywhere in the app.
public struct Money: Hashable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Builds an amount from major units (e.g. dollars), rounding half-up
    /// to the nearest minor unit.
    public init(majorUnits: Decimal, currency: Currency) {
        let scale = Self.powerOfTen(currency.minorUnitScale)
        let scaled = (majorUnits as NSDecimalNumber).multiplying(by: NSDecimalNumber(decimal: scale))
        let rounded = scaled.rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )
        self.init(minorUnits: rounded.int64Value, currency: currency)
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    public var isNegative: Bool { minorUnits < 0 }
    public var isZero: Bool { minorUnits == 0 }

    public func adding(_ other: Money) throws -> Money {
        guard other.currency.code == currency.code else {
            throw AccountingError.currencyMismatch(expected: currency.code, actual: other.currency.code)
        }
        let (sum, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw AccountingError.amountOverflow }
        return Money(minorUnits: sum, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        guard other.currency.code == currency.code else {
            throw AccountingError.currencyMismatch(expected: currency.code, actual: other.currency.code)
        }
        let (result, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else { throw AccountingError.amountOverflow }
        return Money(minorUnits: result, currency: currency)
    }

    public func negated() throws -> Money {
        let (result, overflow) = Int64(0).subtractingReportingOverflow(minorUnits)
        guard !overflow else { throw AccountingError.amountOverflow }
        return Money(minorUnits: result, currency: currency)
    }

    /// Converts to another currency. `rate` is the price of one major unit
    /// of this currency expressed in major units of `target`.
    public func converted(to target: Currency, rate: Decimal) throws -> Money {
        guard rate > 0 else { throw AccountingError.invalidExchangeRate }
        let major = Decimal(minorUnits) / Self.powerOfTen(currency.minorUnitScale)
        let targetMajor = major * rate
        return Money(majorUnits: targetMajor, currency: target)
    }

    /// Human readable amount with grouping separators, e.g. "1,500,000 IRR".
    public func formatted() -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = currency.minorUnitScale
        formatter.maximumFractionDigits = currency.minorUnitScale
        let major = Decimal(minorUnits) / Self.powerOfTen(currency.minorUnitScale)
        let digits = formatter.string(from: NSDecimalNumber(decimal: major)) ?? String(minorUnits)
        return "\(digits) \(currency.code)"
    }

    private static func powerOfTen(_ exponent: Int) -> Decimal {
        var result: Decimal = 1
        for _ in 0..<exponent { result *= 10 }
        return result
    }
}
