import ProMeData
import ProMeDomain
import SwiftUI

@main
struct ProMeApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                #if os(macOS)
                .frame(minWidth: 1040, minHeight: 640)
                #endif
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Transaction")) {
                    appModel.quickEntryPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button(String(localized: "New Transfer")) {
                    appModel.presentedSheet = .transfer
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(String(localized: "New Account")) {
                    appModel.presentedSheet = .account
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button(String(localized: "New Category")) {
                    appModel.presentedSheet = .category
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button(String(localized: "New Business")) {
                    appModel.presentedSheet = .business
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button(String(localized: "New Debt")) {
                    appModel.presentedSheet = .debt
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button(String(localized: "New Loan")) {
                    appModel.presentedSheet = .loan
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button(String(localized: "New Insurance")) {
                    appModel.presentedSheet = .insurance
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button(String(localized: "New Task")) {
                    appModel.presentedSheet = .task
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button(String(localized: "New Appointment")) {
                    appModel.presentedSheet = .appointment
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(String(localized: "New Note")) {
                    appModel.presentedSheet = .note
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button(String(localized: "New Alert")) {
                    appModel.presentedSheet = .alert
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }

            CommandGroup(after: .newItem) {
                Button(String(localized: "Search Transactions")) {
                    appModel.selectedRoute = .transactions
                    appModel.focusSearchToken += 1
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu(String(localized: "Navigate")) {
                ForEach(Array(AppRoute.allCases.enumerated()), id: \.element) { index, route in
                    if index < 9 {
                        Button(route.title) {
                            appModel.selectedRoute = route
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else {
                        Button(route.title) {
                            appModel.selectedRoute = route
                        }
                    }
                }
            }

            CommandGroup(after: .help) {
                Button(String(localized: "Keyboard Shortcuts")) {
                    appModel.showShortcuts = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appModel)
        }
        #endif
    }
}
