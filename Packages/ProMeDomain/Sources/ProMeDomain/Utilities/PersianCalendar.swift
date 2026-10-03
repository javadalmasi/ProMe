import Foundation

/// Persian (Jalali) calendar helpers built on Foundation's own
/// `Calendar(identifier: .persian)`.
///
/// The database always stores standard `Date` values; conversion to Jalali
/// happens here, at presentation time, so switching the display calendar
/// never rewrites stored data.
public struct PersianCalendar: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var persian = Calendar(identifier: .persian)
        persian.timeZone = timeZone
        calendar = persian
    }

    public struct Components: Equatable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int

        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }
    }

    public func components(of date: Date) -> Components {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return Components(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Formats as "1405/07/07".
    public func formatted(_ date: Date) -> String {
        let parts = components(of: date)
        return String(format: "%04d/%02d/%02d", parts.year, parts.month, parts.day)
    }

    /// Builds a date at noon for the given Jalali components. Noon keeps the
    /// result safely inside the requested day across time zone shifts.
    public func date(from components: Components) -> Date? {
        calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 12
        ))
    }

    /// First instant of the Jalali month containing `date`.
    public func startOfMonth(for date: Date) -> Date? {
        calendar.dateInterval(of: .month, for: date)?.start
    }
}
