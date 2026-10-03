import Foundation

/// A currency known to the app. Amounts are stored as integer minor units
/// (see `Money`), so `minorUnitScale` decides how many of those units make
/// up one major unit (100 cents for USD, a single rial for IRR).
public struct Currency: Hashable, Sendable {
    public let code: String
    public let minorUnitScale: Int
    public let symbol: String

    public init(code: String, minorUnitScale: Int, symbol: String) {
        self.code = code
        self.minorUnitScale = minorUnitScale
        self.symbol = symbol
    }

    public static let irr = Currency(code: "IRR", minorUnitScale: 0, symbol: "﷼")
    /// Toman — one tenth of a Rial, the common unofficial unit.
    public static let toman = Currency(code: "IRT", minorUnitScale: 0, symbol: "تومان")
    public static let usd = Currency(code: "USD", minorUnitScale: 2, symbol: "$")
    public static let eur = Currency(code: "EUR", minorUnitScale: 2, symbol: "€")
    public static let gbp = Currency(code: "GBP", minorUnitScale: 2, symbol: "£")
    public static let aed = Currency(code: "AED", minorUnitScale: 2, symbol: "د.إ")
    public static let lira = Currency(code: "TRY", minorUnitScale: 2, symbol: "₺")

    public static let known: [String: Currency] = [
        irr.code: irr,
        toman.code: toman,
        usd.code: usd,
        eur.code: eur,
        gbp.code: gbp,
        aed.code: aed,
        lira.code: lira,
    ]

    /// Resolves a stored currency code. Unknown codes fall back to a
    /// two-decimal currency so older data never crashes the app.
    public static func resolving(_ code: String) -> Currency {
        let upper = code.uppercased()
        return known[upper] ?? Currency(code: upper, minorUnitScale: 2, symbol: upper)
    }

    /// Display suffix for amounts; Toman is written out.
    public var displayCode: String {
        code == Currency.toman.code ? "تومان" : code
    }
}
