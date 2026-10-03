import ProMeDomain
import SwiftUI

/// Vector logo for an Iranian bank: a rounded square in the bank's brand
/// color with the Persian monogram. Avoids bundling trademarked artwork
/// while keeping each bank visually distinct.
public struct BankLogo: View {
    public let bank: IranianBank
    public var size: CGFloat = 32

    public init(_ bank: IranianBank, size: CGFloat = 32) {
        self.bank = bank
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.brandTint(bank.colorHex), Color.brandTint(bank.colorHex).opacity(0.82)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(bank.monogram)
                    .font(.custom(AppFont.familyName, size: size * 0.52).weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.08)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .accessibilityLabel(Text(bank.name))
    }
}

/// Parses "#RRGGBB" into a Color, falling back to the accent color.
public extension Color {
    static func brandTint(_ hex: String) -> Color {
        Color(hexString: hex) ?? .accentColor
    }

    /// Parses "#RRGGBB"; nil when the string is not a valid hex color.
    static func fromHex(_ hex: String) -> Color? {
        Color(hexString: hex)
    }

    init?(hexString: String) {
        var sanitized = hexString.trimmingCharacters(in: .whitespaces)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
