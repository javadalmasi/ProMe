import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Appointments with exact-time (hourly) reminders. Upcoming appointments
/// surface first; past ones stay in a collapsible history.
struct AppointmentsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var appointments: [AppointmentMO] = []
    @State private var showHistory = false
    @State private var editorPresented = false
    @State private var editingAppointment: AppointmentMO?

    var body: some View {
        let (upcoming, past) = partitioned
        VStack(spacing: 0) {
            if appointments.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "clock.badge.checkmark",
                        title: String(localized: "No appointments"),
                        detail: String(localized: "Schedule meetings and get reminders right on time.")
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    Section(String(localized: "Upcoming")) {
                        if upcoming.isEmpty {
                            Text(String(localized: "Nothing scheduled ahead."))
                                .font(.appCallout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(upcoming, id: \.objectID) { appointment in
                            row(appointment)
                        }
                        .onDelete { offsets in
                            delete(offsets, in: upcoming)
                        }
                    }
                    if !past.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showHistory.animation(.snappy(duration: 0.25))) {
                                ForEach(past, id: \.objectID) { appointment in
                                    row(appointment)
                                }
                            } label: {
                                Label(String(localized: "Past"), systemImage: "clock.arrow.circlepath")
                                    .font(.appCallout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .appListStyle()
                .animation(.snappy(duration: 0.25), value: showHistory)
            }
        }
        .navigationTitle(String(localized: "Appointments"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorPresented = true
                } label: {
                    Label(String(localized: "New Appointment"), systemImage: "plus")
                }
            }
        }
        .task(id: appModel.dataEpoch) { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $editorPresented, onDismiss: reload) {
            AppointmentEditor()
        }
        .sheet(item: $editingAppointment, onDismiss: reload) { appointment in
            AppointmentEditor(appointment: appointment)
        }
    }

    private var partitioned: (upcoming: [AppointmentMO], past: [AppointmentMO]) {
        let upcoming = appointments.filter { !$0.isPastNow }
        let past = appointments.filter(\.isPastNow).sorted { $0.startsAt > $1.startsAt }
        return (upcoming, past)
    }

    private func reload() {
        guard let services = appModel.services else { return }
        appointments = (try? services.appointments.all()) ?? []
    }

    private func delete(_ offsets: IndexSet, in source: [AppointmentMO]) {
        let targets = offsets.compactMap { source.indices.contains($0) ? source[$0] : nil }
        for appointment in targets {
            try? appModel.services?.appointments.delete(appointment)
        }
        reload()
        appModel.bumpData()
    }

    @ViewBuilder
    private func row(_ appointment: AppointmentMO) -> some View {
        Button {
            editingAppointment = appointment
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(timeOrAllDay(appointment))
                        .font(.appCallout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(appointment.isPastNow ? Color.secondary : Color.accentColor)
                    Text(Format.dateText(appointment.startsAt))
                        .font(.appCaption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 84, alignment: .leading)
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.35)).frame(width: 2, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appointment.title)
                        .font(.appBody.weight(.medium))
                        .strikethrough(appointment.status == .cancelled)
                    HStack(spacing: 8) {
                        if let location = appointment.location, !location.isEmpty {
                            Label(location, systemImage: "mappin")
                                .font(.appCaption2)
                        }
                        Label(String(localized: "Reminder \(appointment.reminderMinutesBefore) min before"), systemImage: "bell")
                            .font(.appCaption2)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if appointment.status == .confirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(ProMeColor.income)
                        .font(.appCallout)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func timeOrAllDay(_ appointment: AppointmentMO) -> String {
        appointment.isAllDay ? String(localized: "All day") : Format.timeText(appointment.startsAt)
    }
}

extension AppointmentMO {
    /// True when the appointment start lies in the past.
    var isPastNow: Bool {
        startsAt < Date()
    }
}

/// Create / edit sheet for an appointment with a precise reminder offset.
struct AppointmentEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let appointment: AppointmentMO?

    init(appointment: AppointmentMO? = nil) {
        self.appointment = appointment
        _title = State(initialValue: appointment?.title ?? "")
        _location = State(initialValue: appointment?.location ?? "")
        _notes = State(initialValue: appointment?.notes ?? "")
        _startsAt = State(initialValue: appointment?.startsAt ?? Date.now.addingTimeInterval(3600))
        _hasEnd = State(initialValue: appointment?.endsAt != nil)
        _endsAt = State(initialValue: appointment?.endsAt ?? Date.now.addingTimeInterval(7200))
        _isAllDay = State(initialValue: appointment?.isAllDay ?? false)
        _reminderMinutes = State(initialValue: Int(appointment?.reminderMinutesBefore ?? 30))
        _status = State(initialValue: appointment?.status ?? .scheduled)
    }

    @State private var title: String
    @State private var location: String
    @State private var notes: String
    @State private var startsAt: Date
    @State private var hasEnd: Bool
    @State private var endsAt: Date
    @State private var isAllDay: Bool
    @State private var reminderMinutes: Int
    @State private var status: AppointmentStatus

    private let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Appointment")) {
                    TextField(String(localized: "Title"), text: $title)
                    TextField(String(localized: "Location"), text: $location)
                    TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                Section(String(localized: "When")) {
                    Toggle(String(localized: "All day"), isOn: $isAllDay.animation(.snappy(duration: 0.2)))
                    DatePicker(
                        String(localized: "Starts"),
                        selection: $startsAt,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    Toggle(String(localized: "Has end"), isOn: $hasEnd.animation(.snappy(duration: 0.2)))
                    if hasEnd {
                        DatePicker(
                            String(localized: "Ends"),
                            selection: $endsAt,
                            in: startsAt ... .distantFuture,
                            displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                    }
                }
                Section(String(localized: "Hourly alert")) {
                    Picker(String(localized: "Reminder"), selection: $reminderMinutes) {
                        ForEach(reminderOptions, id: \.self) { minutes in
                            Text(reminderName(minutes)).tag(minutes)
                        }
                    }
                    Picker(String(localized: "Status"), selection: $status) {
                        Text(String(localized: "Scheduled")).tag(AppointmentStatus.scheduled)
                        Text(String(localized: "Confirmed")).tag(AppointmentStatus.confirmed)
                        Text(String(localized: "Completed")).tag(AppointmentStatus.completed)
                        Text(String(localized: "Cancelled")).tag(AppointmentStatus.cancelled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(appointment == nil ? String(localized: "New Appointment") : String(localized: "Edit Appointment"))
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
        .frame(width: 440, height: 540)
        #endif
    }

    private func reminderName(_ minutes: Int) -> String {
        switch minutes {
        case 0:
            return String(localized: "At time of event")
        case 1440:
            return String(localized: "1 day before")
        default:
            if minutes < 60 {
                return String(localized: "\(minutes) minutes before")
            }
            let hours = minutes / 60
            return String(localized: "\(hours) hour(s) before")
        }
    }

    private func save() {
        guard let services = appModel.services else { return }
        if let appointment {
            appointment.title = title.trimmingCharacters(in: .whitespaces)
            appointment.location = location.isEmpty ? nil : location
            appointment.notes = notes.isEmpty ? nil : notes
            appointment.startsAt = startsAt
            appointment.endsAt = hasEnd ? endsAt : nil
            appointment.isAllDay = isAllDay
            appointment.reminderMinutesBefore = Int32(reminderMinutes)
            appointment.status = status
            try? services.appointments.save(appointment)
        } else {
            _ = try? services.appointments.create(
                title: title.trimmingCharacters(in: .whitespaces),
                notes: notes.isEmpty ? nil : notes,
                location: location.isEmpty ? nil : location,
                startsAt: startsAt,
                endsAt: hasEnd ? endsAt : nil,
                isAllDay: isAllDay,
                reminderMinutesBefore: reminderMinutes,
                status: status
            )
        }
        appModel.bumpData()
        dismiss()
    }
}
