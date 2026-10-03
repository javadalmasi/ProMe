import ProMeData
import ProMeDomain
import Foundation

/// Snapshot of the personal-life state shown on the dashboard.
struct LifeTodaySummary {
    var openTasks: [TaskItemMO] = []
    var doneCount = 0
    var nextAppointment: AppointmentMO?
    var alertCount = 0

    var isEmpty: Bool {
        openTasks.isEmpty && nextAppointment == nil && alertCount == 0
    }
}
