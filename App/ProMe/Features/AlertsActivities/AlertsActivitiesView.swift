import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Alerts (day-level, repeatable) and the daily activity log, in two tabs.
struct AlertsActivitiesView: View {
    @Environment(AppModel.self) private var appModel

    enum Tab: String, CaseIterable {
        case alerts
        case activities

        var title: String {
            switch self {
            case .alerts: String(localized: "Alerts")
            case .activities: String(localized: "Daily Activities")
            }
        }

        var icon: String {
            switch self {
            case .alerts: "bell.badge"
            case .activities: "figure.walk.motion"
            }
        }
    }

    @State private var tab: Tab = .alerts
    @State private var alerts: [AlertItemMO] = []
    @State private var activities: [ActivityEntryMO] = []
    @State private var alertEditorPresented = false
    @State private var activityEditorPresented = false
    @State private var editingAlert: AlertItemMO?

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Section"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            switch tab {
            case .alerts: alertsList
            case .activities: activitiesList
            }
        }
        .navigationTitle(String(localized: "Alerts & Activities"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if tab == .alerts {
                        alertEditorPresented = true
                    } else {
                        activityEditorPresented = true
                    }
                } label: {
                    Label(
                        tab == .alerts ? String(localized: "New Alert") : String(localized: "Log Activity"),
                        systemImage: "plus"
                    )
                }
            }
        }
        .task(id: "\(tab)|\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $alertEditorPresented, onDismiss: reload) {
            AlertEditor()
        }
        .sheet(item: $editingAlert, onDismiss: reload) { alert in
            AlertEditor(alert: alert)
        }
        .sheet(isPresented: $activityEditorPresented, onDismiss: reload) {
            ActivityQuickEntry(date: .now)
        }
    }

    // MARK: - Alerts

    private var alertsList: some View {
        Group {
            if alerts.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "bell.slash",
                        title: String(localized: "No alerts yet"),
                        detail: String(localized: "Alerts remind you once or repeatedly — daily, weekly or monthly.")
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    ForEach(alerts, id: \.objectID) { alert in
                        alertRow(alert)
                    }
                    .onDelete { offsets in
                        deleteAlerts(at: offsets)
                    }
                }
                .appListStyle()
            }
        }
    }

    @ViewBuilder
    private func alertRow(_ alert: AlertItemMO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.severity == .urgent ? "exclamationmark.triangle.fill" : "bell.fill")
                .foregroundStyle(severityColor(alert.severity))
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title).font(.appBody.weight(.medium))
                if let message = alert.message, !message.isEmpty {
                    Text(message).font(.appCaption).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    Text(Format.dateTimeText(alert.dueAt))
                    if alert.repeatRule != .once {
                        Label(repeatName(alert.repeatRule), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.appCaption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alert.isActive },
                set: { newValue in
                    alert.isActive = newValue
                    try? appModel.services?.alerts.save(alert)
                    appModel.bumpData()
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
        .opacity(alert.isActive ? 1 : 0.55)
        .contextMenu {
            Button(String(localized: "Edit")) { editingAlert = alert }
            Button(String(localized: "Delete"), role: .destructive) {
                try? appModel.services?.alerts.delete(alert)
                reload()
                appModel.bumpData()
            }
        }
    }

    private func deleteAlerts(at offsets: IndexSet) {
        let targets = offsets.compactMap { alerts.indices.contains($0) ? alerts[$0] : nil }
        for alert in targets {
            try? appModel.services?.alerts.delete(alert)
        }
        reload()
        appModel.bumpData()
    }

    private func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .info: Color.blue
        case .important: Color.orange
        case .urgent: ProMeColor.expense
        }
    }

    private func repeatName(_ repeatRule: AlertRepeat) -> String {
        switch repeatRule {
        case .once: String(localized: "Once")
        case .daily: String(localized: "Every Day")
        case .weekly: String(localized: "Every Week")
        case .monthly: String(localized: "Every Month")
        }
    }

    // MARK: - Activities

    private var activitiesList: some View {
        Group {
            if activities.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "figure.walk.motion",
                        title: String(localized: "No activities logged"),
                        detail: String(localized: "Log what you do each day to build a personal record.")
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    ForEach(activities, id: \.objectID) { activity in
                        activityRow(activity)
                    }
                    .onDelete { offsets in
                        deleteActivities(at: offsets)
                    }
                }
                .appListStyle()
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: ActivityEntryMO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ActivityGlyph.icon(activity.category))
                .font(.appTitle3)
                .foregroundStyle(Color.teal)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title).font(.appBody.weight(.medium))
                HStack(spacing: 5) {
                    Text(Format.dateTimeText(activity.date))
                    if let duration = activity.durationMinutes?.intValue, duration > 0 {
                        Label(String(localized: "\(duration) min"), systemImage: "timer")
                    }
                }
                .font(.appCaption2)
                .foregroundStyle(.secondary)
                if let note = activity.note, !note.isEmpty {
                    Text(note).font(.appCaption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            categoryBadge(activity.category)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func categoryBadge(_ category: ActivityCategory) -> some View {
        Text(categoryName(category))
            .font(.appCaption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.teal.opacity(0.12)))
            .foregroundStyle(Color.teal)
    }

    private func deleteActivities(at offsets: IndexSet) {
        let targets = offsets.compactMap { activities.indices.contains($0) ? activities[$0] : nil }
        for activity in targets {
            try? appModel.services?.activities.delete(activity)
        }
        reload()
        appModel.bumpData()
    }

    private func categoryName(_ category: ActivityCategory) -> String {
        switch category {
        case .work: String(localized: "Work")
        case .personal: String(localized: "Personal")
        case .health: String(localized: "Health")
        case .learning: String(localized: "Learning")
        case .finance: String(localized: "Finance")
        case .other: String(localized: "Other")
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        alerts = (try? services.alerts.active()) ?? []
        activities = (try? services.activities.recent()) ?? []
    }
}

/// Editor for an alert (one-shot or repeating).
struct AlertEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let alert: AlertItemMO?

    init(alert: AlertItemMO? = nil) {
        self.alert = alert
        _title = State(initialValue: alert?.title ?? "")
        _message = State(initialValue: alert?.message ?? "")
        _severity = State(initialValue: alert?.severity ?? .info)
        _repeatRule = State(initialValue: alert?.repeatRule ?? .once)
        _dueAt = State(initialValue: alert?.dueAt ?? Date.now.addingTimeInterval(3600))
    }

    @State private var title: String
    @State private var message: String
    @State private var severity: AlertSeverity
    @State private var repeatRule: AlertRepeat
    @State private var dueAt: Date

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Alert")) {
                    TextField(String(localized: "Title"), text: $title)
                    TextField(String(localized: "Message"), text: $message, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                Section(String(localized: "When")) {
                    DatePicker(String(localized: "Date & time"), selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                    Picker(String(localized: "Repeat"), selection: $repeatRule) {
                        ForEach(AlertRepeat.allCases, id: \.self) { option in
                            Text(repeatName(option)).tag(option)
                        }
                    }
                }
                Section(String(localized: "Severity")) {
                    Picker(String(localized: "Severity"), selection: $severity) {
                        Text(String(localized: "Info")).tag(AlertSeverity.info)
                        Text(String(localized: "Important")).tag(AlertSeverity.important)
                        Text(String(localized: "Urgent")).tag(AlertSeverity.urgent)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(alert == nil ? String(localized: "New Alert") : String(localized: "Edit Alert"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 430)
        #endif
    }

    private func save() {
        guard let services = appModel.services else { return }
        if let alert {
            alert.title = title.trimmingCharacters(in: .whitespaces)
            alert.message = message.isEmpty ? nil : message
            alert.severity = severity
            alert.repeatRule = repeatRule
            alert.dueAt = dueAt
            alert.isActive = true
            try? services.alerts.save(alert)
        } else {
            _ = try? services.alerts.add(
                title: title.trimmingCharacters(in: .whitespaces),
                message: message.isEmpty ? nil : message,
                severity: severity,
                repeatRule: repeatRule,
                dueAt: dueAt
            )
        }
        appModel.bumpData()
        dismiss()
    }

    private func repeatName(_ repeatRule: AlertRepeat) -> String {
        switch repeatRule {
        case .once: String(localized: "Once")
        case .daily: String(localized: "Every Day")
        case .weekly: String(localized: "Every Week")
        case .monthly: String(localized: "Every Month")
        }
    }
}

/// Quick activity log entry (also used from the calendar day panel).
struct ActivityQuickEntry: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var title = ""
    @State private var note = ""
    @State private var category: ActivityCategory = .other
    @State private var hasDuration = false
    @State private var duration = 30
    @State private var activityDate: Date

    init(date: Date) {
        self.date = date
        _activityDate = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Activity")) {
                    TextField(String(localized: "What did you do?"), text: $title)
                    TextField(String(localized: "Note"), text: $note, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                Section(String(localized: "Category")) {
                    Picker(String(localized: "Category"), selection: $category) {
                        ForEach(ActivityCategory.allCases, id: \.self) { option in
                            Label(categoryName(option), systemImage: ActivityGlyph.icon(option)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(String(localized: "When")) {
                    DatePicker(String(localized: "Date & time"), selection: $activityDate, displayedComponents: [.date, .hourAndMinute])
                    Toggle(String(localized: "Has duration"), isOn: $hasDuration.animation(.snappy(duration: 0.2)))
                    if hasDuration {
                        Stepper(value: $duration, in: 5 ... 480, step: 5) {
                            Text(String(localized: "\(duration) min"))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Log Activity"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 430)
        #endif
    }

    private func save() {
        guard let services = appModel.services else { return }
        _ = try? services.activities.add(
            title: title.trimmingCharacters(in: .whitespaces),
            note: note.isEmpty ? nil : note,
            date: activityDate,
            category: category,
            durationMinutes: hasDuration ? duration : nil
        )
        appModel.bumpData()
        dismiss()
    }

    private func categoryName(_ option: ActivityCategory) -> String {
        switch option {
        case .work: String(localized: "Work")
        case .personal: String(localized: "Personal")
        case .health: String(localized: "Health")
        case .learning: String(localized: "Learning")
        case .finance: String(localized: "Finance")
        case .other: String(localized: "Other")
        }
    }
}
