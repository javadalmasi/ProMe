import CoreData
import Foundation
import ProMeDomain

@objc(TaskItemMO)
public final class TaskItemMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TaskItemMO> {
        NSFetchRequest<TaskItemMO>(entityName: "TaskItem")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var details: String?
    @NSManaged public var dueDate: Date?
    @NSManaged public var hasTime: Bool
    @NSManaged public var priorityRaw: String
    @NSManaged public var statusRaw: String
    @NSManaged public var repeatRaw: String
    @NSManaged public var dateKey: Int32
    @NSManaged public var reminderMinutesBefore: NSNumber?
    @NSManaged public var completedAt: Date?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var repeatRule: TaskRepeat {
        get { TaskRepeat(rawValue: repeatRaw) ?? .none }
        set { repeatRaw = newValue.rawValue }
    }

    public var isDone: Bool {
        status == .done
    }
}

@objc(ActivityEntryMO)
public final class ActivityEntryMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ActivityEntryMO> {
        NSFetchRequest<ActivityEntryMO>(entityName: "ActivityEntry")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var note: String?
    @NSManaged public var date: Date
    @NSManaged public var dateKey: Int32
    @NSManaged public var categoryRaw: String
    @NSManaged public var durationMinutes: NSNumber?
    @NSManaged public var createdAt: Date

    public var category: ActivityCategory {
        get { ActivityCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

@objc(AlertItemMO)
public final class AlertItemMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AlertItemMO> {
        NSFetchRequest<AlertItemMO>(entityName: "AlertItem")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var message: String?
    @NSManaged public var severityRaw: String
    @NSManaged public var repeatRaw: String
    @NSManaged public var dueAt: Date
    @NSManaged public var dateKey: Int32
    @NSManaged public var isActive: Bool
    @NSManaged public var lastFiredAt: Date?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    public var severity: AlertSeverity {
        get { AlertSeverity(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    public var repeatRule: AlertRepeat {
        get { AlertRepeat(rawValue: repeatRaw) ?? .once }
        set { repeatRaw = newValue.rawValue }
    }
}

@objc(AppointmentMO)
public final class AppointmentMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AppointmentMO> {
        NSFetchRequest<AppointmentMO>(entityName: "Appointment")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var notes: String?
    @NSManaged public var location: String?
    @NSManaged public var startsAt: Date
    @NSManaged public var endsAt: Date?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var reminderMinutesBefore: Int32
    @NSManaged public var statusRaw: String
    @NSManaged public var dateKey: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    public var status: AppointmentStatus {
        get { AppointmentStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }
}

@objc(NoteMO)
public final class NoteMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NoteMO> {
        NSFetchRequest<NoteMO>(entityName: "Note")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String?
    @NSManaged public var bodyText: String
    @NSManaged public var colorHex: String?
    @NSManaged public var isPinned: Bool
    @NSManaged public var dateKey: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

@objc(PlaceMO)
public final class PlaceMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlaceMO> {
        NSFetchRequest<PlaceMO>(entityName: "Place")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var address: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var notes: String?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    public var category: PlaceCategory {
        get { PlaceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    public var coordinate: (latitude: Double, longitude: Double) {
        (latitude, longitude)
    }
}

@objc(DeletionLogMO)
public final class DeletionLogMO: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DeletionLogMO> {
        NSFetchRequest<DeletionLogMO>(entityName: "DeletionLog")
    }

    @NSManaged public var id: UUID
    @NSManaged public var recordEntity: String
    @NSManaged public var recordID: UUID
    @NSManaged public var deletedAt: Date
}
