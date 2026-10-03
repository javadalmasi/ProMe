import CoreData
import Foundation
import ProMeDomain

/// CRUD and queries for the personal-life entities (tasks, activities,
/// alerts, appointments, notes, places). All entities are scope-free:
/// they belong to the person, not to a financial scope.
@MainActor
public final class TaskService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    @discardableResult
    public func create(
        title: String,
        details: String? = nil,
        dueDate: Date? = nil,
        hasTime: Bool = false,
        priority: TaskPriority = .normal,
        repeatRule: TaskRepeat = .none,
        reminderMinutesBefore: Int? = nil
    ) throws -> TaskItemMO {
        let task = TaskItemMO(context: context)
        task.id = UUID()
        task.title = title
        task.details = details
        task.dueDate = dueDate
        task.hasTime = hasTime
        task.priority = priority
        task.status = .pending
        task.repeatRule = repeatRule
        task.dateKey = Int32(DateKey.make(from: dueDate ?? .now))
        task.reminderMinutesBefore = reminderMinutesBefore.map { NSNumber(value: Int32($0)) }
        task.createdAt = .now
        task.updatedAt = .now
        try controller.saveViewContext()
        return task
    }

    public func save(_ task: TaskItemMO) throws {
        task.updatedAt = .now
        task.dateKey = Int32(DateKey.make(from: task.dueDate ?? task.updatedAt))
        try controller.saveViewContext()
    }

    /// Marks a task done. Repeating tasks roll forward to their next
    /// occurrence instead of closing.
    @discardableResult
    public func complete(_ task: TaskItemMO) throws -> TaskItemMO? {
        task.completedAt = .now
        switch task.repeatRule {
        case .none:
            task.status = .done
            try controller.saveViewContext()
            return task
        case .daily:
            let next = Calendar.current.date(byAdding: .day, value: 1, to: task.dueDate ?? .now) ?? .now
            task.dueDate = next
            task.dateKey = Int32(DateKey.make(from: next))
            task.status = .pending
            task.completedAt = nil
            try controller.saveViewContext()
            return task
        case .weekly:
            let next = Calendar.current.date(byAdding: .day, value: 7, to: task.dueDate ?? .now) ?? .now
            task.dueDate = next
            task.dateKey = Int32(DateKey.make(from: next))
            task.status = .pending
            task.completedAt = nil
            try controller.saveViewContext()
            return task
        }
    }

    public func reopen(_ task: TaskItemMO) throws {
        task.status = .pending
        task.completedAt = nil
        try controller.saveViewContext()
    }

    public func delete(_ task: TaskItemMO) throws {
        context.delete(task)
        try controller.saveViewContext()
    }

    public func all(includeCompleted: Bool = true) throws -> [TaskItemMO] {
        let request = TaskItemMO.fetchRequest()
        if !includeCompleted {
            request.predicate = NSPredicate(format: "statusRaw != %@", TaskStatus.done.rawValue)
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "statusRaw", ascending: true),
            NSSortDescriptor(key: "dueDate", ascending: true),
        ]
        return try context.fetch(request)
    }

    /// Tasks due on a specific compact day key.
    public func tasks(onDayKey key: Int32) throws -> [TaskItemMO] {
        let request = TaskItemMO.fetchRequest()
        request.predicate = NSPredicate(format: "dateKey == %d", key)
        request.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true)]
        return try context.fetch(request)
    }

    public func today() throws -> [TaskItemMO] {
        try tasks(onDayKey: Int32(DateKey.make(from: .now)))
    }

    public func overdue() throws -> [TaskItemMO] {
        let request = TaskItemMO.fetchRequest()
        request.predicate = NSPredicate(
            format: "statusRaw IN %@ AND dateKey < %d",
            [TaskStatus.pending.rawValue, TaskStatus.inProgress.rawValue],
            DateKey.make(from: .now)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "dateKey", ascending: true)]
        return try context.fetch(request)
    }
}

@MainActor
public final class ActivityService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    @discardableResult
    public func add(
        title: String,
        note: String? = nil,
        date: Date = .now,
        category: ActivityCategory = .other,
        durationMinutes: Int? = nil
    ) throws -> ActivityEntryMO {
        let entry = ActivityEntryMO(context: context)
        entry.id = UUID()
        entry.title = title
        entry.note = note
        entry.date = date
        entry.dateKey = Int32(DateKey.make(from: date))
        entry.category = category
        entry.durationMinutes = durationMinutes.map { NSNumber(value: Int32($0)) }
        entry.createdAt = .now
        try controller.saveViewContext()
        return entry
    }

    public func delete(_ entry: ActivityEntryMO) throws {
        context.delete(entry)
        try controller.saveViewContext()
    }

    public func entries(onDayKey key: Int32) throws -> [ActivityEntryMO] {
        let request = ActivityEntryMO.fetchRequest()
        request.predicate = NSPredicate(format: "dateKey == %d", key)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    public func recent(limit: Int = 100) throws -> [ActivityEntryMO] {
        let request = ActivityEntryMO.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = limit
        return try context.fetch(request)
    }
}

@MainActor
public final class AlertService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    @discardableResult
    public func add(
        title: String,
        message: String? = nil,
        severity: AlertSeverity = .info,
        repeatRule: AlertRepeat = .once,
        dueAt: Date = .now
    ) throws -> AlertItemMO {
        let alert = AlertItemMO(context: context)
        alert.id = UUID()
        alert.title = title
        alert.message = message
        alert.severity = severity
        alert.repeatRule = repeatRule
        alert.dueAt = dueAt
        alert.dateKey = Int32(DateKey.make(from: dueAt))
        alert.isActive = true
        alert.createdAt = .now
        alert.updatedAt = .now
        try controller.saveViewContext()
        return alert
    }

    public func save(_ alert: AlertItemMO) throws {
        alert.updatedAt = .now
        alert.dateKey = Int32(DateKey.make(from: alert.dueAt))
        try controller.saveViewContext()
    }

    public func delete(_ alert: AlertItemMO) throws {
        context.delete(alert)
        try controller.saveViewContext()
    }

    public func active() throws -> [AlertItemMO] {
        let request = AlertItemMO.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "dueAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Advances a repeating alert to its next occurrence; one-shot alerts
    /// are deactivated.
    public func markFired(_ alert: AlertItemMO) throws {
        alert.lastFiredAt = .now
        switch alert.repeatRule {
        case .once:
            alert.isActive = false
        case .daily:
            alert.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: alert.dueAt) ?? alert.dueAt
        case .weekly:
            alert.dueAt = Calendar.current.date(byAdding: .day, value: 7, to: alert.dueAt) ?? alert.dueAt
        case .monthly:
            alert.dueAt = Calendar.current.date(byAdding: .month, value: 1, to: alert.dueAt) ?? alert.dueAt
        }
        alert.dateKey = Int32(DateKey.make(from: alert.dueAt))
        try controller.saveViewContext()
    }
}

@MainActor
public final class AppointmentService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    @discardableResult
    public func create(
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startsAt: Date,
        endsAt: Date? = nil,
        isAllDay: Bool = false,
        reminderMinutesBefore: Int = 30,
        status: AppointmentStatus = .scheduled
    ) throws -> AppointmentMO {
        let appointment = AppointmentMO(context: context)
        appointment.id = UUID()
        appointment.title = title
        appointment.notes = notes
        appointment.location = location
        appointment.startsAt = startsAt
        appointment.endsAt = endsAt
        appointment.isAllDay = isAllDay
        appointment.reminderMinutesBefore = Int32(reminderMinutesBefore)
        appointment.status = status
        appointment.dateKey = Int32(DateKey.make(from: startsAt))
        appointment.createdAt = .now
        appointment.updatedAt = .now
        try controller.saveViewContext()
        return appointment
    }

    public func save(_ appointment: AppointmentMO) throws {
        appointment.updatedAt = .now
        appointment.dateKey = Int32(DateKey.make(from: appointment.startsAt))
        try controller.saveViewContext()
    }

    public func delete(_ appointment: AppointmentMO) throws {
        context.delete(appointment)
        try controller.saveViewContext()
    }

    public func all() throws -> [AppointmentMO] {
        let request = AppointmentMO.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startsAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Appointments starting between two instants (inclusive).
    public func appointments(from start: Date, to end: Date) throws -> [AppointmentMO] {
        let request = AppointmentMO.fetchRequest()
        request.predicate = NSPredicate(format: "startsAt >= %@ AND startsAt <= %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "startsAt", ascending: true)]
        return try context.fetch(request)
    }

    public func upcoming(withinDays days: Int = 7) throws -> [AppointmentMO] {
        try appointments(from: .now, to: Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .distantFuture)
    }
}

@MainActor
public final class NoteService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    @discardableResult
    public func create(title: String? = nil, body: String, colorHex: String? = nil) throws -> NoteMO {
        let note = NoteMO(context: context)
        note.id = UUID()
        note.title = title
        note.bodyText = body
        note.colorHex = colorHex
        note.isPinned = false
        note.dateKey = Int32(DateKey.make(from: .now))
        note.createdAt = .now
        note.updatedAt = .now
        try controller.saveViewContext()
        return note
    }

    public func save(_ note: NoteMO) throws {
        note.updatedAt = .now
        try controller.saveViewContext()
    }

    public func delete(_ note: NoteMO) throws {
        context.delete(note)
        try controller.saveViewContext()
    }

    /// All notes, pinned first, then most recently updated.
    public func all() throws -> [NoteMO] {
        let request = NoteMO.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
        ]
        return try context.fetch(request)
    }
}

@MainActor
public final class PlaceService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    @discardableResult
    public func create(
        name: String,
        category: PlaceCategory = .other,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        notes: String? = nil
    ) throws -> PlaceMO {
        let place = PlaceMO(context: context)
        place.id = UUID()
        place.name = name
        place.category = category
        place.address = address
        place.latitude = latitude
        place.longitude = longitude
        place.notes = notes
        place.isFavorite = false
        place.createdAt = .now
        place.updatedAt = .now
        try controller.saveViewContext()
        return place
    }

    public func save(_ place: PlaceMO) throws {
        place.updatedAt = .now
        try controller.saveViewContext()
    }

    public func delete(_ place: PlaceMO) throws {
        context.delete(place)
        try controller.saveViewContext()
    }

    public func all() throws -> [PlaceMO] {
        let request = PlaceMO.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "isFavorite", ascending: false),
            NSSortDescriptor(key: "name", ascending: true),
        ]
        return try context.fetch(request)
    }
}
