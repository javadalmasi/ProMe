import ProMeDesignSystem
import ProMeData
import ProMeDomain
import SwiftUI

/// Settings: general preferences plus manual backup/restore.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            AboutSettingsView()
                .tabItem { Label(String(localized: "About"), systemImage: "info.circle") }
            SyncSettingsView()
                .tabItem { Label(String(localized: "Sync"), systemImage: "arrow.triangle.2.circlepath.icloud") }
            BackupSettingsView()
                .tabItem { Label(String(localized: "Backup"), systemImage: "externaldrive") }
            DiagnosticsView()
                .tabItem { Label(String(localized: "Diagnostics"), systemImage: "stethoscope") }
        }
        #if os(macOS)
        .frame(width: 620, height: 500)
        #endif
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("calendarPreference") private var calendarPreferenceRaw = CalendarPreference.persian.rawValue
    @AppStorage("digitStyle") private var digitStyleRaw = DigitStyle.latin.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = "IRR"
    @AppStorage("appLanguage") private var appLanguageRaw = "fa"

    @State private var showRestartPrompt = false

    private let knownCurrencies = ["IRT", "IRR", "USD", "EUR", "GBP", "AED", "TRY"]

    /// Languages discovered from the shipped string catalog, so adding a
    /// translation file automatically offers the language here.
    private var availableLanguages: [String] {
        var codes = Set(Bundle.main.localizations)
        codes.formUnion(["en", "fa"])
        return ["system"] + codes.sorted()
    }

    private func languageName(_ code: String) -> String {
        let locale = Locale.current
        let native = locale.localizedString(forLanguageCode: code) ?? code
        let english = Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? code
        if native == english {
            return english.capitalized
        }
        return "\(native.capitalized) (\(english.capitalized))"
    }

    var body: some View {
        Form {
            Picker(String(localized: "App Language"), selection: $appLanguageRaw) {
                Text(String(localized: "System")).tag("system")
                ForEach(availableLanguages.filter { $0 != "system" }, id: \.self) { code in
                    Text(languageName(code)).tag(code)
                }
            }
            .onChange(of: appLanguageRaw) { _, newValue in
                if newValue == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                }
                showRestartPrompt = true
            }
            Picker(String(localized: "Calendar"), selection: $calendarPreferenceRaw) {
                Text(String(localized: "Persian")).tag(CalendarPreference.persian.rawValue)
                Text(String(localized: "Gregorian")).tag(CalendarPreference.gregorian.rawValue)
            }
            Picker(String(localized: "Digits"), selection: $digitStyleRaw) {
                Text(String(localized: "Persian")).tag(DigitStyle.persian.rawValue)
                Text(String(localized: "Latin")).tag(DigitStyle.latin.rawValue)
            }
            Picker(String(localized: "Main Currency"), selection: $baseCurrency) {
                ForEach(knownCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            Text(String(localized: "Dates are stored in the standard calendar and only displayed in your calendar."))
                .font(.appCaption)
                .foregroundStyle(.secondary)
            Text(String(localized: "Want ProMe in your language? See the translation guide in the project repository — new languages appear here automatically."))
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

private struct BackupSettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var backups: [BackupService.BackupInfo] = []
    @State private var statusMessage: String?
    @State private var restoring: BackupService.BackupInfo?

    var body: some View {
        Form {
            Section {
                HStack {
                    Button(String(localized: "Backup Now")) { runBackup() }
                    Spacer()
                    if let statusMessage {
                        Text(statusMessage).font(.appCaption).foregroundStyle(.secondary)
                    }
                }
                Text(String(localized: "Backups are portable SQLite files in a dated folder."))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Backup History")) {
                if backups.isEmpty {
                    Text(String(localized: "No backups yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(backups) { backup in
                    HStack {
                        Image(systemName: "externaldrive")
                        VStack(alignment: .leading) {
                            Text(backup.folder.lastPathComponent).font(.appCallout)
                            Text(Format.dateText(backup.date)).font(.appCaption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(String(localized: "Restore")) { restoring = backup }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { backups = appModel.services?.backup.recordedBackups() ?? [] }
        .confirmationDialog(
            String(localized: "Restore this backup?"),
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Restore"), role: .destructive) { runRestore() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "The current data will be replaced with the backup contents."))
        }
    }

    private func runBackup() {
        guard let services = appModel.services else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Choose where to store the backup folder.")
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            do {
                let destination = try services.backup.backup(to: folder)
                services.backup.recordBackupFolder(destination)
                Task { @MainActor in
                    backups = services.backup.recordedBackups()
                    statusMessage = String(localized: "Backup completed.")
                }
            } catch {
                Task { @MainActor in
                    statusMessage = error.localizedDescription
                }
            }
        }
        #else
        // On iOS/iPadOS backups live in the app's Documents/Backups folder
        // and can be shared out from the history list.
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = try services.backup.backup(to: documents.appendingPathComponent("Backups", isDirectory: true))
            services.backup.recordBackupFolder(destination)
            backups = services.backup.recordedBackups()
            statusMessage = String(localized: "Backup completed.")
        } catch {
            statusMessage = error.localizedDescription
        }
        #endif
    }

    private func runRestore() {
        guard let services = appModel.services, let backup = restoring else { return }
        do {
            try services.backup.restore(from: backup.folder)
            statusMessage = String(localized: "Restored. Views refresh as you navigate.")
        } catch {
            statusMessage = error.localizedDescription
        }
        backups = services.backup.recordedBackups()
        restoring = nil
    }
}


/// Recent handled errors and events, copyable for support.
private struct DiagnosticsView: View {
    @State private var store = ProMeLog.Store.shared
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "No issues recorded."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.entries.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.appCaption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            }
            HStack {
                Text(String(localized: "Financial amounts are never logged."))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Clear")) { store.clear() }
                Button(String(localized: "Copy Report")) {
                    Clip.copy(store.entries.joined(separator: "\n"))
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                .disabled(store.entries.isEmpty)
            }
            .padding(12)
        }
    }
}

/// End-to-end encrypted multi-device sync over an S3-compatible bucket.
/// The master key never leaves the device unencrypted: it is wrapped with
/// a PBKDF2-derived password key before upload, and every snapshot is
/// signed with the device's Ed25519 key.
struct SyncSettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var endpoint = "https://s3.amazonaws.com"
    @State private var region = "us-east-1"
    @State private var bucket = ""
    @State private var prefix = "prome"
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""

    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var isConfigured = false

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Snapshots are encrypted (AES-GCM) with a key that is password-wrapped in your bucket, and every device signs its uploads with its own Ed25519 key. Without the password nobody — not even the storage provider — can read your data."))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "S3 Storage")) {
                TextField(String(localized: "Endpoint"), text: $endpoint)
                TextField(String(localized: "Region"), text: $region)
                TextField(String(localized: "Bucket"), text: $bucket)
                TextField(String(localized: "Key Prefix"), text: $prefix)
                TextField(String(localized: "Access Key"), text: $accessKey)
                SecureField(String(localized: "Secret Key"), text: $secretKey)
            }

            Section(String(localized: "Vault Password")) {
                SecureField(String(localized: "Password"), text: $password)
                SecureField(String(localized: "Confirm Password"), text: $passwordConfirmation)
                Text(String(localized: "The password is not stored anywhere. It is required when adding a new device."))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if isConfigured {
                    Button {
                        run { try await sync() }
                    } label: {
                        Label(String(localized: "Sync Now"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isWorking)
                    Button(String(localized: "Disconnect"), role: .destructive) {
                        appModel.services?.sync.disconnect()
                        isConfigured = false
                        statusMessage = String(localized: "Sync disconnected. Remote data is untouched.")
                    }
                } else {
                    Picker(String(localized: "Setup"), selection: $mode) {
                        Text(String(localized: "Create a new vault (first device)")).tag(Mode.create)
                        Text(String(localized: "Join an existing vault (new device)")).tag(Mode.join)
                    }
                    #if os(macOS)
                    .pickerStyle(.radioGroup)
                    #endif
                    Button {
                        run { try await setup() }
                    } label: {
                        Label(
                            mode == .create
                                ? String(localized: "Create Encrypted Vault")
                                : String(localized: "Join Encrypted Vault"),
                            systemImage: "lock.shield"
                        )
                    }
                    .disabled(!formComplete || isWorking)
                }
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let config = appModel.services?.sync.config {
                endpoint = config.endpoint
                region = config.region
                bucket = config.bucket
                prefix = config.prefix
                accessKey = config.accessKey
                isConfigured = appModel.services?.sync.isConfigured ?? false
            }
        }
    }

    private enum Mode {
        case create
        case join
    }

    @State private var mode: Mode = .create

    private var formComplete: Bool {
        !endpoint.isEmpty && !bucket.isEmpty && !accessKey.isEmpty &&
            !secretKey.isEmpty && password.count >= 8 &&
            (mode == .join || password == passwordConfirmation)
    }

    private func setup() async throws {
        guard let sync = appModel.services?.sync else { return }
        let secret = secretKey
        try sync.configure(
            S3Config(
                endpoint: endpoint.trimmingCharacters(in: .whitespaces),
                region: region.trimmingCharacters(in: .whitespaces),
                bucket: bucket.trimmingCharacters(in: .whitespaces),
                prefix: prefix.trimmingCharacters(in: .whitespaces),
                accessKey: accessKey.trimmingCharacters(in: .whitespaces)
            ),
            secretKey: secret
        )
        switch mode {
        case .create:
            try await sync.createVault(password: password)
            statusMessage = String(localized: "Vault created. This device can now push and pull encrypted snapshots.")
        case .join:
            try await sync.joinVault(password: password)
            statusMessage = String(localized: "Joined the vault. Run a sync to pull this account's data.")
        }
        password = ""
        passwordConfirmation = ""
        isConfigured = true
    }

    private func sync() async throws {
        guard let sync = appModel.services?.sync else { return }
        try await sync.syncNow()
        appModel.bumpData()
        if case .done(let message) = sync.phase {
            statusMessage = message
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        isWorking = true
        statusMessage = nil
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// About: version, free-software notice and the original repository.
struct AboutSettingsView: View {
    private let repositoryURL = URL(string: "https://github.com/javadalmasi/ProMe")!

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image("AppIcon").resizable().frame(width: 56, height: 56).cornerRadius(12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ProMe").font(.appTitle3.weight(.bold))
                        Text(String(localized: "Your personal suite: money and life, together."))
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Version \(versionText)"))
                            .font(.appCaption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(String(localized: "Project")) {
                LabeledContent(String(localized: "Original repository")) {
                    Link("github.com/javadalmasi/ProMe", destination: repositoryURL)
                }
                LabeledContent(String(localized: "Development")) {
                    Text(String(localized: "Built by the free software group."))
                }
                LabeledContent(String(localized: "License")) {
                    Text(String(localized: "GPL-3.0-or-later"))
                }
            }

            Section {
                Text(String(localized: "ProMe is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. Translations, bug reports and patches are welcome in the original repository."))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
