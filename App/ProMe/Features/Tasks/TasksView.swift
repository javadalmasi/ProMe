import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Daily task list with priorities, repeat rules and reminders.
struct TasksView: View {
    @Environment(AppModel.self) private var appModel

    enum Filter: String, CaseIterable {
        case today
        case open
        case all

        var title: String {
            switch self {
            case .today: String(localized: "Today")
            case .open: String(localized: "Open")
            case .all: String(localized: "All")
            }
        }
    }

    @State private var tasks: [TaskItemMO] = []
    @State private var filter: Filter = .today
    @State private var editorPresented = false
    @State private var editingTask: TaskItemMO?

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Filter"), selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if visibleTasks.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "checklist",
                        title: String(localized: "No tasks here"),
                        detail: String(localized: "Add your first task with the + button.")
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    ForEach(visibleTasks, id: \.objectID) { task in
                        taskRow(task)
                    }
                    .onDelete { offsets in
                        delete(at: offsets)
                    }
                }
                .appListStyle()
                .animation(.snappy(duration: 0.25), value: filter)
            }
        }
        .navigationTitle(String(localized: "Daily Tasks"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorPresented = true
                } label: {
                    Label(String(localized: "New Task"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(filter)|\(appModel.dataEpoch)") { reload() }
        .sheet(isPresented: $editorPresented, onDismiss: { reload() }) {
            TaskEditor()
        }
        .sheet(item: $editingTask, onDismiss: { reload() }) { task in
            TaskEditor(task: task)
        }
    }

    private var visibleTasks: [TaskItemMO] {
        let todayKey = Int32(DateKey.make(from: .now))
        switch filter {
        case .today:
            return tasks.filter { !$0.isDone && ($0.dateKey == todayKey || $0.dateKey < todayKey) }
        case .open:
            return tasks.filter { !$0.isDone }
        case .all:
            return tasks
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        tasks = (try? services.tasks.all(includeCompleted: true)) ?? []
    }

    private func delete(at offsets: IndexSet) {
        guard let services = appModel.services else { return }
        let targets = offsets.compactMap { visibleTasks.indices.contains($0) ? visibleTasks[$0] : nil }
        for task in targets {
            try? services.tasks.delete(task)
        }
        reload()
        appModel.bumpData()
    }

    @ViewBuilder
    private func taskRow(_ task: TaskItemMO) -> some View {
        Button {
            if task.isDone {
                try? appModel.services?.tasks.reopen(task)
            } else {
                _ = try? appModel.services?.tasks.complete(task)
            }
            reload()
            appModel.bumpData()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? ProMeColor.income : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.appBody.weight(task.priority == .urgent || task.priority == .high ? .semibold : .regular))
                        .strikethrough(task.isDone)
                    if let due = task.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: task.hasTime ? "clock" : "calendar")
                                .font(.appCaption2)
                            Text(task.hasTime ? Format.timeText(due) : Format.dateText(due))
                                .font(.appCaption)
                        }
                        .foregroundStyle(isOverdue(task) ? ProMeColor.expense : Color.secondary)
                    }
                }
                Spacer()
                if task.repeatRule != .none {
                    Image(systemName: task.repeatRule == .daily ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.appCaption)
                        .foregroundStyle(.tertiary)
                }
                priorityBadge(task.priority)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "Edit")) { editingTask = task }
            Button(String(localized: "Delete"), role: .destructive) {
                try? appModel.services?.tasks.delete(task)
                reload()
                appModel.bumpData()
            }
        }
    }

    private func isOverdue(_ task: TaskItemMO) -> Bool {
        guard let due = task.dueDate, !task.isDone else { return false }
        return task.hasTime ? due < .now : DateKey.make(from: due) < DateKey.make(from: .now)
    }

    @ViewBuilder
    private func priorityBadge(_ priority: TaskPriority) -> some View {
        switch priority {
        case .urgent:
            Label(String(localized: "Urgent"), systemImage: "exclamationmark.2")
                .font(.appCaption2.weight(.bold))
                .labelStyle(.iconOnly)
                .foregroundStyle(ProMeColor.expense)
        case .high:
            Label(String(localized: "High"), systemImage: "exclamationmark")
                .font(.appCaption2.weight(.bold))
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.orange)
        default:
            EmptyView()
        }
    }
}

/// Create / edit sheet for a task.
struct TaskEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let task: TaskItemMO?

    init(task: TaskItemMO? = nil) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _hasTime = State(initialValue: task?.hasTime ?? false)
        _dueDate = State(initialValue: task?.dueDate ?? .now)
        _priority = State(initialValue: task?.priority ?? .normal)
        _repeatRule = State(initialValue: task?.repeatRule ?? .none)
        _reminderMinutes = State(initialValue: task?.reminderMinutesBefore?.intValue ?? 0)
    }

    @State private var title: String
    @State private var details: String
    @State private var hasDueDate: Bool
    @State private var hasTime: Bool
    @State private var dueDate: Date
    @State private var priority: TaskPriority
    @State private var repeatRule: TaskRepeat
    @State private var reminderMinutes: Int

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Task")) {
                    TextField(String(localized: "Title"), text: $title)
                    TextField(String(localized: "Details"), text: $details, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                Section(String(localized: "When")) {
                    Toggle(String(localized: "Has due date"), isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(String(localized: "Date"), selection: $dueDate, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        Toggle(String(localized: "Include time"), isOn: $hasTime.animation(.snappy(duration: 0.2)))
                    }
                }
                Section(String(localized: "Details")) {
                    Picker(String(localized: "Priority"), selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { option in
                            Text(priorityName(option)).tag(option)
                        }
                    }
                    Picker(String(localized: "Repeat"), selection: $repeatRule) {
                        ForEach(TaskRepeat.allCases, id: \.self) { option in
                            Text(repeatName(option)).tag(option)
                        }
                    }
                    if hasDueDate && hasTime {
                        Picker(String(localized: "Reminder"), selection: $reminderMinutes) {
                            Text(String(localized: "None")).tag(0)
                            Text(String(localized: "5 minutes before")).tag(5)
                            Text(String(localized: "15 minutes before")).tag(15)
                            Text(String(localized: "30 minutes before")).tag(30)
                            Text(String(localized: "1 hour before")).tag(60)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(task == nil ? String(localized: "New Task") : String(localized: "Edit Task"))
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
        .frame(width: 420, height: 480)
        #endif
    }

    private func save() {
        guard let services = appModel.services else { return }
        let due = hasDueDate ? dueDate : nil
        let reminder: Int? = hasDueDate && hasTime && reminderMinutes > 0 ? reminderMinutes : nil
        if let task {
            task.title = title.trimmingCharacters(in: .whitespaces)
            task.details = details.isEmpty ? nil : details
            task.dueDate = due
            task.hasTime = hasTime
            task.priority = priority
            task.repeatRule = repeatRule
            task.reminderMinutesBefore = reminder.map { NSNumber(value: Int32($0)) }
            try? services.tasks.save(task)
        } else {
            _ = try? services.tasks.create(
                title: title.trimmingCharacters(in: .whitespaces),
                details: details.isEmpty ? nil : details,
                dueDate: due,
                hasTime: hasTime,
                priority: priority,
                repeatRule: repeatRule,
                reminderMinutesBefore: reminder
            )
        }
        appModel.bumpData()
        dismiss()
    }

    private func priorityName(_ option: TaskPriority) -> String {
        switch option {
        case .low: String(localized: "Low")
        case .normal: String(localized: "Normal")
        case .high: String(localized: "High")
        case .urgent: String(localized: "Urgent")
        }
    }

    private func repeatName(_ option: TaskRepeat) -> String {
        switch option {
        case .none: String(localized: "Never")
        case .daily: String(localized: "Every Day")
        case .weekly: String(localized: "Every Week")
        }
    }
}
