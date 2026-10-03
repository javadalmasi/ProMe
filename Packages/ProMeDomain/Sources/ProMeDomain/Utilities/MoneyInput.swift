import Foundation

/// Parses user-typed amounts, accepting Persian/Arabic digits and both the
/// Persian (٫) and Latin decimal separators.
public enum MoneyInput {
    public static func parseDecimal(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let map: [Character: Character] = [
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "٫": ".", "٬": ".",
        ]
        text = String(text.map { map[$0] ?? $0 })
        text = text.filter { $0 != "،" && $0 != "," && $0 != " " }
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Parses to minor units, rounding half-up at the currency's scale.
    public static func parseMinorUnits(_ raw: String, currency: Currency) -> Int64? {
        guard let decimal = parseDecimal(raw), decimal != 0 else { return nil }
        let money = Money(majorUnits: decimal, currency: currency)
        return money.minorUnits
    }
}
