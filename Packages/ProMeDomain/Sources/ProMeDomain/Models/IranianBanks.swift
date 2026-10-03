import Foundation

/// Registry of Iranian banks and credit institutions. Used to prefill the
/// account editor from a card number, to draw brand-tinted logos, and to
/// validate Iranian IBANs (Sheba).
public struct IranianBank: Sendable, Identifiable, Hashable {
    /// Short latin identifier (stable, used for logo assets).
    public let id: String
    /// Official Persian name.
    public let name: String
    public let englishName: String
    /// Brand color as "#RRGGBB" (approximation, used for the vector logo).
    public let colorHex: String
    /// Persian monogram drawn inside the vector logo.
    public let monogram: String
    /// Known 6-digit card BINs.
    public let cardBINs: [String]
    /// 3-digit Sheba (IBAN) bank code where known.
    public let shebaCode: String?

    public init(
        id: String, name: String, englishName: String, colorHex: String,
        monogram: String, cardBINs: [String] = [], shebaCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.colorHex = colorHex
        self.monogram = monogram
        self.cardBINs = cardBINs
        self.shebaCode = shebaCode
    }

    /// All banks, in the order shown in pickers (state banks first).
    public static let all: [IranianBank] = [
        IranianBank(id: "bmi", name: "بانک ملی", englishName: "Bank Melli", colorHex: "#D71920", monogram: "م", cardBINs: ["603799"], shebaCode: "017"),
        IranianBank(id: "mellat", name: "بانک ملت", englishName: "Bank Mellat", colorHex: "#A6192E", monogram: "م", cardBINs: ["610433", "991975"], shebaCode: "012"),
        IranianBank(id: "saderat", name: "بانک صادرات", englishName: "Bank Saderat", colorHex: "#004B8D", monogram: "ص", cardBINs: ["603769"], shebaCode: "019"),
        IranianBank(id: "tejarat", name: "بانک تجارت", englishName: "Tejarat Bank", colorHex: "#F26522", monogram: "ت", cardBINs: ["627353"], shebaCode: "018"),
        IranianBank(id: "sepah", name: "بانک سپه", englishName: "Bank Sepah", colorHex: "#00703C", monogram: "س", cardBINs: ["589210"], shebaCode: "015"),
        IranianBank(id: "keshavarzi", name: "بانک کشاورزی", englishName: "Agriculture Bank", colorHex: "#6CBE45", monogram: "ک", cardBINs: ["603770", "639217"], shebaCode: "016"),
        IranianBank(id: "maskan", name: "بانک مسکن", englishName: "Housing Bank", colorHex: "#0072BC", monogram: "م", cardBINs: ["628023"], shebaCode: "014"),
        IranianBank(id: "refah", name: "بانک رفاه", englishName: "Refah Bank", colorHex: "#005EB8", monogram: "ر", cardBINs: ["589463"], shebaCode: "013"),
        IranianBank(id: "sanat", name: "بانک صنعت و معدن", englishName: "Bank of Industry & Mine", colorHex: "#00539F", monogram: "ص", cardBINs: ["627760"], shebaCode: "011"),
        IranianBank(id: "tose", name: "بانک توسعه صادرات", englishName: "Export Development Bank", colorHex: "#00583D", monogram: "ت", cardBINs: ["207177", "627648"], shebaCode: "020"),
        IranianBank(id: "post", name: "بانک پست", englishName: "Post Bank", colorHex: "#FFB81C", monogram: "پ", cardBINs: ["627795"], shebaCode: "021"),
        IranianBank(id: "qavamin", name: "بانک قوامین", englishName: "Ghavamin Bank", colorHex: "#0072CE", monogram: "ق", cardBINs: ["639346"]),
        IranianBank(id: "parsian", name: "بانک پارسیان", englishName: "Parsian Bank", colorHex: "#1B2A6B", monogram: "پ", cardBINs: ["622106", "639194"], shebaCode: "054"),
        IranianBank(id: "pasargad", name: "بانک پاسارگاد", englishName: "Bank Pasargad", colorHex: "#F39200", monogram: "پ", cardBINs: ["502229", "639347"], shebaCode: "057"),
        IranianBank(id: "saman", name: "بانک سامان", englishName: "Saman Bank", colorHex: "#0083CA", monogram: "س", cardBINs: ["621986"], shebaCode: "056"),
        IranianBank(id: "karafarin", name: "بانک کارآفرین", englishName: "Karafarin Bank", colorHex: "#5C2D91", monogram: "ک", cardBINs: ["627488"], shebaCode: "053"),
        IranianBank(id: "en", name: "بانک اقتصاد نوین", englishName: "EN Bank", colorHex: "#009A44", monogram: "ا", cardBINs: ["627412"], shebaCode: "055"),
        IranianBank(id: "ayandeh", name: "بانک آینده", englishName: "Ayandeh Bank", colorHex: "#00A3E0", monogram: "آ", cardBINs: ["636214"], shebaCode: "062"),
        IranianBank(id: "shahr", name: "بانک شهر", englishName: "Shahr Bank", colorHex: "#E4002B", monogram: "ش", cardBINs: ["502806", "502938"]),
        IranianBank(id: "sarmayeh", name: "بانک سرمایه", englishName: "Sarmayeh Bank", colorHex: "#003366", monogram: "س", cardBINs: ["639607"], shebaCode: "058"),
        IranianBank(id: "sina", name: "بانک سینا", englishName: "Sina Bank", colorHex: "#007A33", monogram: "س", shebaCode: "059"),
        IranianBank(id: "meb", name: "بانک خاورمیانه", englishName: "Middle East Bank", colorHex: "#003DA5", monogram: "خ", cardBINs: ["505801"], shebaCode: "061"),
        IranianBank(id: "iranzamin", name: "بانک ایران زمین", englishName: "Iran Zamin Bank", colorHex: "#00954C", monogram: "ا", cardBINs: ["505785", "505416"]),
        IranianBank(id: "gardeshgari", name: "بانک گردشگری", englishName: "Tourism Bank", colorHex: "#00B5E2", monogram: "گ", cardBINs: ["505901"]),
        IranianBank(id: "tosee", name: "بانک توسعه تعاون", englishName: "Cooperative Development Bank", colorHex: "#008C48", monogram: "ت", cardBINs: ["502959"]),
        IranianBank(id: "melliran", name: "بانک مهر ایران", englishName: "Mehr Iran Bank", colorHex: "#00A651", monogram: "م", cardBINs: ["606373"]),
        IranianBank(id: "resalat", name: "بانک قرض‌الحسنه رسالت", englishName: "Resalat Bank", colorHex: "#005B94", monogram: "ر", cardBINs: ["504172"]),
    ]

    /// Looks up a bank by the leading digits of a card number.
    public static func matching(cardNumber: String) -> IranianBank? {
        let digits = CardValidator.digits(in: cardNumber)
        guard digits.count >= 6 else { return nil }
        let bin = String(digits.prefix(6))
        return all.first { $0.cardBINs.contains(bin) }
    }

    public static func matching(shebaCode: String) -> IranianBank? {
        all.first { $0.shebaCode == shebaCode }
    }

    public static func named(_ name: String) -> IranianBank? {
        all.first { $0.name == name || $0.englishName == name }
    }
}

/// Validation helpers for Iranian card numbers and IBANs.
public enum CardValidator {
    /// Keeps only ASCII digits.
    public static func digits(in text: String) -> String {
        text.filter { $0.isASCII && $0.isNumber }
    }

    /// Standard Luhn checksum used by Iranian bank cards (16 digits).
    public static func luhnValid(_ number: String) -> Bool {
        let digits = digits(in: number)
        guard digits.count >= 12 else { return false }
        var sum = 0
        let reversed = digits.reversed()
        for (index, character) in reversed.enumerated() {
            guard let digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// Groups a card number as "6037-9912-3456-7890".
    public static func formattedCardNumber(_ number: String) -> String {
        let digits = digits(in: number)
        return stride(from: 0, to: digits.count, by: 4).map { start in
            let end = min(start + 4, digits.count)
            let from = digits.index(digits.startIndex, offsetBy: start)
            let to = digits.index(digits.startIndex, offsetBy: end)
            return String(digits[from ..< to])
        }
        .joined(separator: "-")
    }
}

/// Iranian IBAN (Sheba) validation: "IR" + 2 check digits + 22 digits
/// (26 characters), validated with the ISO 13616 mod-97 test.
public enum ShebaValidator {
    /// Extracts the 3-digit bank code (the digits right after the check
    /// digits, i.e. characters 5–7).
    public static func bankCode(of sheba: String) -> String? {
        let normalized = normalize(sheba)
        guard normalized.count == 26 else { return nil }
        let start = normalized.index(normalized.startIndex, offsetBy: 4)
        let end = normalized.index(start, offsetBy: 3)
        return String(normalized[start ..< end])
    }

    /// Full mod-97 validation of an Iranian Sheba.
    public static func isValid(_ sheba: String) -> Bool {
        let normalized = normalize(sheba)
        guard normalized.count == 26, normalized.hasPrefix("IR") else { return false }
        // Move the first four characters ("IR" + check digits) to the end,
        // replace I with 18 and R with 27, then mod 97 over the digits.
        let rearranged = String(normalized.dropFirst(4)) + "1827" + String(normalized.prefix(4).dropFirst(2))
        var remainder = 0
        for character in rearranged {
            guard let digit = character.wholeNumberValue, digit >= 0 else { return false }
            remainder = (remainder * 10 + digit) % 97
        }
        return remainder == 1
    }

    /// "IR" + digits only (Persian digits are not accepted).
    private static func normalize(_ sheba: String) -> String {
        let upper = sheba.uppercased().replacingOccurrences(of: " ", with: "")
        guard let first = upper.first, let second = upper.dropFirst().first else { return "" }
        let rest = CardValidator.digits(in: String(upper.dropFirst(2)))
        return String(first) + String(second) + rest
    }
}
