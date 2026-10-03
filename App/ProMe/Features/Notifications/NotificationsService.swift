import Foundation
import ProMeData
import ProMeDomain
@preconcurrency import UserNotifications

/// Local reminders for the whole app: recurring payments due soon, tasks
/// with reminders, hourly appointment alerts, and repeating alerts.
/// Notifications are best-effort: permission denials are silent.
enum NotificationsService {
    static func refreshReminders(appModel: AppModel) {
        guard let services = appModel.services else { return }
        let center = UNUserNotificationCenter.current()

        var requests: [UNNotificationRequest] = []

        // Recurring payments due within the next week.
        let upcoming = (try? services.recurring.upcoming(withinDays: 7)) ?? []
        requests += upcoming.map { makeRecurringRequest(for: $0) }

        // Tasks with a reminder and a time.
        let tasks = ((try? services.tasks.today()) ?? []) +
            ((try? services.tasks.overdue()) ?? [])
        for task in tasks where !task.isDone && task.hasTime {
            if let due = task.dueDate, let minutes = task.reminderMinutesBefore?.intValue, minutes > 0 {
                requests.append(makeReminderRequest(
                    id: "task-\(task.id.uuidString)",
                    title: String(localized: "Task Reminder"),
                    body: task.title,
                    fireDate: due.addingTimeInterval(TimeInterval(-minutes * 60))
                ))
            }
        }

        // Appointments: reminder at the configured offset.
        let appointments = (try? services.appointments.upcoming(withinDays: 7)) ?? []
        for appointment in appointments where appointment.status != .cancelled && !appointment.isPastNow {
            let fireDate = max(
                appointment.startsAt.addingTimeInterval(TimeInterval(-Int(appointment.reminderMinutesBefore) * 60)),
                .now.addingTimeInterval(5)
            )
            requests.append(makeReminderRequest(
                id: "appointment-\(appointment.id.uuidString)",
                title: String(localized: "Appointment Reminder"),
                body: appointment.location.map { "\(appointment.title) — \($0)" } ?? appointment.title,
                fireDate: fireDate
            ))
        }

        // Repeating alerts.
        let alerts = (try? services.alerts.active()) ?? []
        for alert in alerts where alert.dueAt > .now.addingTimeInterval(-60) {
            requests.append(makeReminderRequest(
                id: "alert-\(alert.id.uuidString)-\(Int(alert.dueAt.timeIntervalSince1970))",
                title: alertTitle(alert.severity),
                body: alert.message.map { "\(alert.title) — \($0)" } ?? alert.title,
                fireDate: alert.dueAt
            ))
        }

        // Build everything up-front on the main actor; the async callbacks
        // only hand over plain request values. UNNotificationRequest is not
        // marked Sendable, so the binding is unchecked on purpose.
        nonisolated(unsafe) let payload = Array(requests.prefix(60))

        center.removeAllPendingNotificationRequests()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule(payload, center: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        schedule(payload, center: center)
                    }
                }
            default:
                break
            }
        }
    }

    private static func alertTitle(_ severity: AlertSeverity) -> String {
        switch severity {
        case .info: String(localized: "Alert")
        case .important: String(localized: "Important Alert")
        case .urgent: String(localized: "Urgent Alert")
        }
    }

    private static func makeRecurringRequest(for item: RecurringTransactionMO) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Upcoming Payment")
        let name = item.memo ?? item.category?.name ?? item.kind.displayName
        let amount = Format.amount(item.amountMinor, code: item.currencyCode)
        content.body = String(localized: "\(name): \(amount) is due on \(Format.dateText(item.nextDueAt)).")
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.nextDueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "recurring-\(item.id.uuidString)-\(Int(item.nextDueAt.timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
    }

    private static func makeReminderRequest(id: String, title: String, body: String, fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func schedule(_ requests: [UNNotificationRequest], center: UNUserNotificationCenter) {
        for request in requests {
            center.add(request)
        }
    }
}
