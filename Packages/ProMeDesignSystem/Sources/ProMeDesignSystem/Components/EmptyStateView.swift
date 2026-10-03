import SwiftUI

/// Centered placeholder shown when a list is empty or an error state has
/// nothing more useful to display. Callers pass localized strings.
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let detail: String

    public init(systemImage: String, title: String, detail: String) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: ProMeSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.appTitle3.weight(.semibold))
            Text(detail)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ProMeSpacing.extraLarge)
    }
}
