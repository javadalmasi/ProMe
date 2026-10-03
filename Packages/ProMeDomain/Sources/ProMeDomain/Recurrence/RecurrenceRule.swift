import Foundation

public enum RecurrenceFrequency: String, Sendable, CaseIterable, Codable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
}

/// A repeat rule for recurring transactions. Month-based steps clamp the
/// day to the target month's length (Jan 31 + 1 month → Feb 28/29), so a
/// rent due on the 31st never silently skips a month.
public struct RecurrenceRule: Hashable, Sendable, Codable {
    public let frequency: RecurrenceFrequency
    public let interval: Int

    public init(frequency: RecurrenceFrequency, interval: Int = 1) {
        self.frequency = frequency
        self.interval = max(1, interval)
    }

    /// First occurrence strictly after `date`, anchored to the series
    /// start. Month-based steps keep the anchor's day-of-month and clamp it
    /// to the target month's length (Jan 31 → Feb 28 → Mar 31), so a rent
    /// due on the 31st never silently skips or drifts.
    public func next(after date: Date, from anchor: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .monthly:
            return monthStep(after: date, anchor: anchor, monthsPerStep: interval, calendar: calendar)
        case .quarterly:
            return monthStep(after: date, anchor: anchor, monthsPerStep: 3 * interval, calendar: calendar)
        case .yearly:
            return monthStep(after: date, anchor: anchor, monthsPerStep: 12 * interval, calendar: calendar)
        }
    }

    /// Convenience variant that re-anchors on every call. Only suitable
    /// for day- and week-based rules where no drift can occur.
    public func next(after date: Date, calendar: Calendar) -> Date? {
        next(after: date, from: date, calendar: calendar)
    }

    /// Occurrences at or after `anchor` and before `end` (exclusive).
    public func occurrences(from anchor: Date, before end: Date, calendar: Calendar, limit: Int = 500) -> [Date] {
        var result: [Date] = []
        var current = anchor
        while result.count < limit, current < end {
            result.append(current)
            guard let following = next(after: current, from: anchor, calendar: calendar) else { break }
            current = following
        }
        return result
    }

    /// Month-index arithmetic anchored on `anchor`: picks the first step
    /// whose (possibly clamped) occurrence falls strictly after `date`.
    private func monthStep(after date: Date, anchor: Date, monthsPerStep: Int, calendar: Calendar) -> Date? {
        let anchorComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: anchor)
        guard let anchorYear = anchorComponents.year, let anchorMonth = anchorComponents.month,
              let anchorDay = anchorComponents.day else {
            return nil
        }
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        guard let dateYear = dateComponents.year, let dateMonth = dateComponents.month else {
            return nil
        }
        let anchorIndex = anchorYear * 12 + (anchorMonth - 1)
        let dateIndex = dateYear * 12 + (dateMonth - 1)
        var steps = max(0, (dateIndex - anchorIndex) / monthsPerStep)

        while steps <= 10_000 {
            guard let candidate = monthOccurrence(
                steps: steps, anchorYear: anchorYear, anchorMonth: anchorMonth,
                anchorDay: anchorDay, anchorTime: anchorComponents, monthsPerStep: monthsPerStep, calendar: calendar
            ) else {
                return nil
            }
            if candidate > date {
                return candidate
            }
            steps += 1
        }
        return nil
    }

    private func monthOccurrence(
        steps: Int,
        anchorYear: Int,
        anchorMonth: Int,
        anchorDay: Int,
        anchorTime: DateComponents,
        monthsPerStep: Int,
        calendar: Calendar
    ) -> Date? {
        let total = anchorYear * 12 + (anchorMonth - 1) + monthsPerStep * steps
        let year = total / 12
        let month = total % 12 + 1
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: first) else {
            return nil
        }
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: min(anchorDay, dayRange.count),
            hour: anchorTime.hour ?? 12,
            minute: anchorTime.minute ?? 0
        ))
    }
}
