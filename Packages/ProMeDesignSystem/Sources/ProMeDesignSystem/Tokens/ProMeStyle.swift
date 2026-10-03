import SwiftUI

/// Shared color semantics. Color is only ever a secondary signal — amounts
/// always carry an explicit sign as well (accessibility rule).
public enum ProMeColor {
    public static let income = Color.green
    public static let expense = Color.red
    public static let transfer = Color.blue
    public static let neutral = Color.secondary
}

/// Shared spacing and corner radius tokens.
public enum ProMeSpacing {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let extraLarge: CGFloat = 24
    public static let cardCorner: CGFloat = 10
}

/// A quiet, text-like button style used inside list rows. Uses the native
/// link style on macOS and a borderless tinted style elsewhere.
public struct AppLinkButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .buttonStyle(.link)
        #else
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .tint(.accentColor)
            .buttonStyle(.plain)
        #endif
    }
}

public extension ButtonStyle where Self == AppLinkButtonStyle {
    static var appLink: AppLinkButtonStyle { AppLinkButtonStyle() }
}

/// Cross-platform list styling: striped inset tables on macOS, grouped
/// inset lists on iOS/iPadOS.
public extension View {
    @ViewBuilder
    func appListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset(alternatesRowBackgrounds: true))
        #else
        listStyle(.insetGrouped)
        #endif
    }
}
