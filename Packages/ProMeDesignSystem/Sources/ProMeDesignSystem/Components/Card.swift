import SwiftUI

/// Standard surface container for dashboard cards and form sections.
public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(ProMeSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ProMeSpacing.cardCorner)
                    .fill(.background.secondary)
            )
    }
}

/// Convenience modifier wrapping content in a `Card`.
public extension View {
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(ProMeSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ProMeSpacing.cardCorner)
                    .fill(.background.secondary)
            )
    }
}
