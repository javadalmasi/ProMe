import Foundation

/// Resolves reporting periods in the user's chosen calendar. Stored dates
/// stay Gregorian; only period boundaries come from the display calendar.
public struct PeriodResolver: Sendable {
    public let preference: CalendarPreference

    public init(preference: CalendarPreference) {
        self.preference = preference
    }

    public var calendar: Calendar {
        Calendar(identifier: preference == .persian ? .persian : .gregorian)
    }

    /// Inclusive start / exclusive end of the display month containing `date`.
    public func monthContaining(_ date: Date) -> (start: Date, end: Date) {
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            let start = calendar.startOfDay(for: date)
            return (start, start)
        }
        return (interval.start, interval.end)
    }

    /// The last `count` months ending with the month of `date`, oldest first.
    public func lastMonths(_ count: Int, endingAt date: Date) -> [(start: Date, end: Date)] {
        var result: [(start: Date, end: Date)] = []
        var cursor = monthContaining(date).start
        for _ in 0..<max(0, count) {
            let month = monthContaining(cursor)
            result.append(month)
            guard let previous = calendar.date(byAdding: .month, value: -1, to: month.start) else { break }
            cursor = previous
        }
        return result.reversed()
    }

    /// Compact month label like "1405/07" or "2026/09".
    public func monthLabel(forMonthStart start: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: start)
        return String(format: "%04d/%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
