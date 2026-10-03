import Foundation

/// Compact Gregorian day key (`yyyyMMdd`) used for fast grouping,
/// filtering and indexing regardless of the user's display calendar.
/// Computed in UTC so the same instant always maps to the same key.
public enum DateKey {
    public static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }()

    public static func make(from date: Date, calendar: Calendar = utcCalendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}
