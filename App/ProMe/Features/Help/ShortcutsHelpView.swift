import ProMeDesignSystem
import SwiftUI

/// ⌘/ — every keyboard shortcut in one place.
struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let title: String
    }

    private let rows: [Row] = [
        Row(keys: "⌘N", title: String(localized: "New Transaction")),
        Row(keys: "⌘⇧T", title: String(localized: "New Transfer")),
        Row(keys: "⌘⇧A", title: String(localized: "New Account")),
        Row(keys: "⌘⇧C", title: String(localized: "New Category")),
        Row(keys: "⌘⇧B", title: String(localized: "New Business")),
        Row(keys: "⌘⇧D", title: String(localized: "New Debt")),
        Row(keys: "⌘⇧L", title: String(localized: "New Loan")),
        Row(keys: "⌘⇧I", title: String(localized: "New Insurance")),
        Row(keys: "⌘F", title: String(localized: "Search Transactions")),
        Row(keys: "⌘1 … ⌘9", title: String(localized: "Navigate")),
        Row(keys: "⌘E", title: String(localized: "Edit") + " — " + String(localized: "Transactions")),
        Row(keys: "⌘⌫", title: String(localized: "Delete") + " — " + String(localized: "Transactions")),
        Row(keys: "↩", title: String(localized: "Save")),
        Row(keys: "Esc", title: String(localized: "Close")),
        Row(keys: "⌘/", title: String(localized: "This help")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ProMeSpacing.small) {
                Image(systemName: "command.square.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(ProMeColor.transfer)
                Text(String(localized: "Keyboard Shortcuts"))
                    .font(.appTitle3.weight(.semibold))
            }
            .padding(.top, 18)
            .padding(.bottom, 10)

            List(rows) { row in
                HStack(spacing: 14) {
                    Text(row.keys)
                        .font(.appCallout.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        .frame(width: 96, alignment: .leading)
                    Text(row.title)
                        .font(.appCallout)
                }
            }
            .appListStyle()
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button(String(localized: "Close"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
    }
}
