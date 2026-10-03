import Foundation

/// Priority of a personal task.
public enum TaskPriority: String, CaseIterable, Sendable {
    case low
    case normal
    case high
    case urgent
}

/// Lifecycle of a personal task.
public enum TaskStatus: String, CaseIterable, Sendable {
    case pending
    case inProgress
    case done
    case cancelled
}

/// How a task repeats after completion.
public enum TaskRepeat: String, CaseIterable, Sendable {
    case none
    case daily
    case weekly
}

/// Category of a daily activity entry.
public enum ActivityCategory: String, CaseIterable, Sendable {
    case work
    case personal
    case health
    case learning
    case finance
    case other
}

/// How loud an alert is.
public enum AlertSeverity: String, CaseIterable, Sendable {
    case info
    case important
    case urgent
}

/// How an alert repeats.
public enum AlertRepeat: String, CaseIterable, Sendable {
    case once
    case daily
    case weekly
    case monthly
}

/// Lifecycle of an appointment.
public enum AppointmentStatus: String, CaseIterable, Sendable {
    case scheduled
    case confirmed
    case completed
    case cancelled
}

/// Kind of a saved place.
public enum PlaceCategory: String, CaseIterable, Sendable {
    case home
    case work
    case family
    case friends
    case other
}
