import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Professional Jalali month calendar with per-day markers for tasks,
/// appointments, alerts and notes, plus a detail panel for the selected day.
struct CalendarView: View {
    @Environment(AppModel.self) private var appModel

    /// Selected day at noon (safe inside the day across time zones).
    @State private var selectedDay: Date = .now
    @State private var visibleMonthStart: Date
    @State private var agenda: DayAgenda = .empty
    @State private var monthMarkers: Set<Int32> = []
    @State private var slideDirection: Edge = .leading
    @State private var quickEntryKind: QuickLifeEntryKind?

    private let persian = PersianCalendar(timeZone: .current)

    init() {
        _visibleMonthStart = State(initialValue: PersianCalendar(timeZone: .current).startOfMonth(for: .now) ?? .now)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(spacing: 0) {
                ForEach(Weekday.initials, id: \.self) { initial in
                    Text(initial)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            monthGrid
            agendaPanel
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .navigationTitle(String(localized: "Calendar"))
        .task(id: monthKey) { reloadMonth() }
        .onAppear { reloadAgenda() }
        .sheet(item: $quickEntryKind, onDismiss: {
            quickEntryKind = nil
            reloadMonth()
            reloadAgenda()
        }) { entryKind in
            switch entryKind {
            case .activity:
                ActivityQuickEntry(date: selectedDay)
            }
        }
    }

    private var monthKey: String {
        "\(persian.components(of: visibleMonthStart).year)-\(persian.components(of: visibleMonthStart).month)-\(appModel.dataEpoch)"
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                moveMonth(-1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appCallout.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "Previous month")))

            Spacer()

            VStack(spacing: 0) {
                Text(monthTitle)
                    .font(.appTitle3.weight(.bold))
                    .contentTransition(.numericText())
                Text("\(String(localized: "Today")): \(Format.dateText(.now))")
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                moveMonth(1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appCallout.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "Next month")))

            Button(String(localized: "Today")) {
                withAnimation(.snappy(duration: 0.3)) {
                    selectedDay = .now
                    visibleMonthStart = persian.startOfMonth(for: .now) ?? .now
                    slideDirection = .leading
                }
                reloadMonth()
                reloadAgenda()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.leading, 6)
        }
    }

    private var monthTitle: String {
        let components = persian.components(of: visibleMonthStart)
        let month = PersianMonthName.name(components.month)
        return "\(month) \(Format.persianDigits(String(components.year)))"
    }

    private func moveMonth(_ delta: Int) {
        slideDirection = delta > 0 ? .leading : .trailing
        let components = persian.components(of: visibleMonthStart)
        var dc = DateComponents()
        dc.year = components.year
        dc.month = components.month + delta
        dc.day = 1
        if let next = persian.calendar.date(from: dc) {
            withAnimation(.snappy(duration: 0.28)) {
                visibleMonthStart = next
                selectedDay = next
            }
            reloadMonth()
            reloadAgenda()
        }
    }

    // MARK: - Grid

    private var monthGrid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                if let day {
                    dayCell(day)
                        .transition(.opacity.combined(with: .move(edge: slideDirection)))
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: monthKey)
    }

    /// Nil entries pad the grid before the first day of the month.
    private func monthDays() -> [Date?] {
        let start = visibleMonthStart
        guard let interval = persian.calendar.dateInterval(of: .month, for: start) else { return [] }
        let daysCount = Int(interval.duration / 86_400)
        // Persian week starts on Saturday; Foundation numbers it 7
        // (Saturday) … 6 (Friday), so modulo 7 gives the column index.
        let firstWeekday = persian.calendar.component(.weekday, from: interval.start)
        let padding = firstWeekday % 7 // Saturday → 0 … Friday → 6
        var days: [Date?] = Array(repeating: nil, count: padding)
        for index in 0 ..< daysCount {
            days.append(interval.start.addingTimeInterval(TimeInterval(index) * 86_400))
        }
        return days
    }

    private func dayCell(_ day: Date) -> some View {
        let key = Int32(DateKey.make(from: day))
        let isSelected = Int32(DateKey.make(from: selectedDay)) == key
        let isToday = Int32(DateKey.make(from: .now)) == key
        let hasMarkers = monthMarkers.contains(key)
        let components = persian.components(of: day)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
            reloadAgenda()
        } label: {
            VStack(spacing: 3) {
                Text(Format.persianDigits(String(components.day)))
                    .font(.appCallout.weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(
                            isSelected ? Color.accentColor :
                                (isToday ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                    }
                // Marker dots: task / appointment / alert
                HStack(spacing: 2) {
                    if hasMarkers {
                        Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Format.dateText(day)))
    }

    // MARK: - Agenda

    private var agendaPanel: some View {
        DayAgendaView(agenda: agenda, date: selectedDay, onAddActivity: {
            quickEntryKind = .activity
        }, onToggleTask: { task in
            _ = try? appModel.services?.tasks.complete(task)
            reloadMonth()
            reloadAgenda()
        })
        .cardStyle()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Data

    private func reloadMonth() {
        guard let interval = persian.calendar.dateInterval(of: .month, for: visibleMonthStart) else { return }
        let startKey = Int(DateKey.make(from: interval.start))
        let endKey = Int(DateKey.make(from: interval.end.addingTimeInterval(-1)))
        var markers = Set<Int32>()
        if let services = appModel.services, let persistence = appModel.persistence {
            let taskRequest = TaskItemMO.fetchRequest()
            taskRequest.predicate = NSPredicate(format: "dateKey >= %d AND dateKey <= %d", startKey, endKey)
            for task in (try? persistence.container.viewContext.fetch(taskRequest)) ?? [] {
                markers.insert(task.dateKey)
            }
            let appointmentRequest = AppointmentMO.fetchRequest()
            appointmentRequest.predicate = NSPredicate(format: "dateKey >= %d AND dateKey <= %d", startKey, endKey)
            for appointment in (try? persistence.container.viewContext.fetch(appointmentRequest)) ?? [] {
                markers.insert(appointment.dateKey)
            }
        }
        monthMarkers = markers
    }

    private func reloadAgenda() {
        guard let services = appModel.services else {
            agenda = .empty
            return
        }
        let key = Int32(DateKey.make(from: selectedDay))
        let tasks = (try? services.tasks.tasks(onDayKey: key)) ?? []
        let appointments = (try? services.appointments.appointments(
            from: persian.calendar.startOfDay(for: selectedDay),
            to: persian.calendar.date(byAdding: .day, value: 1, to: persian.calendar.startOfDay(for: selectedDay)) ?? .distantFuture
        )) ?? []
        let activities = (try? services.activities.entries(onDayKey: key)) ?? []
        agenda = DayAgenda(tasks: tasks, appointments: appointments, activities: activities)
    }
}

enum QuickLifeEntryKind: String, Identifiable {
    case activity
    var id: String { rawValue }
}

/// One day's tasks, appointments and activities.
struct DayAgenda {
    var tasks: [TaskItemMO] = []
    var appointments: [AppointmentMO] = []
    var activities: [ActivityEntryMO] = []

    static let empty = DayAgenda()

    var isEmpty: Bool {
        tasks.isEmpty && appointments.isEmpty && activities.isEmpty
    }
}

struct DayAgendaView: View {
    let agenda: DayAgenda
    let date: Date
    var onAddActivity: () -> Void
    var onToggleTask: (TaskItemMO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Format.dateText(date))
                    .font(.appHeadline)
                Spacer()
                Button {
                    onAddActivity()
                } label: {
                    Label(String(localized: "Log Activity"), systemImage: "plus.circle")
                        .font(.appCaption)
                }
                .buttonStyle(.borderless)
            }

            if agenda.isEmpty {
                Text(String(localized: "Nothing planned for this day."))
                    .font(.appCallout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            if !agenda.appointments.isEmpty {
                agendaSection(String(localized: "Appointments"), icon: "clock.badge.checkmark") {
                    ForEach(agenda.appointments, id: \.objectID) { appointment in
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.appCaption)
                                .foregroundStyle(Color.orange)
                            Text(appointment.isAllDay
                                ? String(localized: "All day")
                                : Format.timeText(appointment.startsAt))
                                .font(.appCaption.monospacedDigit())
                                .frame(width: 58, alignment: .leading)
                            Text(appointment.title).font(.appCallout)
                            Spacer()
                            if let location = appointment.location, !location.isEmpty {
                                Text(location).font(.appCaption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !agenda.tasks.isEmpty {
                agendaSection(String(localized: "Daily Tasks"), icon: "checklist") {
                    ForEach(agenda.tasks, id: \.objectID) { task in
                        Button {
                            onToggleTask(task)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? ProMeColor.income : Color.secondary)
                                Text(task.title)
                                    .font(.appCallout)
                                    .strikethrough(task.isDone)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                    }
                }
            }

            if !agenda.activities.isEmpty {
                agendaSection(String(localized: "Daily Activities"), icon: "figure.walk") {
                    ForEach(agenda.activities, id: \.objectID) { activity in
                        HStack(spacing: 8) {
                            Image(systemName: ActivityGlyph.icon(activity.category))
                                .font(.appCaption)
                                .foregroundStyle(Color.teal)
                            Text(activity.title).font(.appCallout)
                            Spacer()
                            if let duration = activity.durationMinutes?.intValue, duration > 0 {
                                Text(String(localized: "\(duration) min"))
                                    .font(.appCaption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func agendaSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

enum PersianMonthName {
    static let names = [
        "فروردین", "اردیبهشت", "خرداد",
        "تیر", "مرداد", "شهریور",
        "مهر", "آبان", "آذر",
        "دی", "بهمن", "اسفند",
    ]

    static func name(_ index: Int) -> String {
        names.indices.contains(index - 1) ? names[index - 1] : ""
    }
}

enum Weekday {
    /// Saturday-first initials for the Persian week.
    static let initials = ["ش", "ی", "د", "س", "چ", "پ", "ج"]
}

enum ActivityGlyph {
    static func icon(_ category: ActivityCategory) -> String {
        switch category {
        case .work: "briefcase"
        case .personal: "person"
        case .health: "figure.run"
        case .learning: "book"
        case .finance: "banknote"
        case .other: "circle.dashed"
        }
    }
}
