import Foundation
import ProMeDomain
import Testing

@Suite("Recurrence rules")
struct RecurrenceTests {
    private var calendar: Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return gregorian
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func monthDay(_ date: Date) -> (Int, Int) {
        (calendar.component(.month, from: date), calendar.component(.day, from: date))
    }

    @Test("Month-end clamping: Jan 31 + 1 month lands on Feb 28")
    func clampsMonthEnd() throws {
        let rule = RecurrenceRule(frequency: .monthly)
        let next = try #require(rule.next(after: date(2023, 1, 31), calendar: calendar))
        #expect(monthDay(next) == (2, 28))
    }

    @Test("Leap year: Feb 29 + 12 months clamps to Feb 28")
    func clampsLeapDay() throws {
        let rule = RecurrenceRule(frequency: .yearly)
        let next = try #require(rule.next(after: date(2024, 2, 29), calendar: calendar))
        #expect(monthDay(next) == (2, 28))
    }

    @Test("Quarterly advances three months")
    func quarterly() throws {
        let rule = RecurrenceRule(frequency: .quarterly)
        let next = try #require(rule.next(after: date(2026, 1, 15), calendar: calendar))
        #expect(monthDay(next) == (4, 15))
    }

    @Test("Every-2-weeks interval")
    func biweekly() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2)
        let next = try #require(rule.next(after: date(2026, 9, 1), calendar: calendar))
        #expect(calendar.component(.day, from: next) == 15)
    }

    @Test("Occurrences before an exclusive end date")
    func occurrenceCount() throws {
        let rule = RecurrenceRule(frequency: .monthly)
        let dates = rule.occurrences(from: date(2026, 1, 1), before: date(2026, 4, 1), calendar: calendar)
        #expect(dates.count == 3)
    }

    @Test("31st of month stays on the 31st in long months and clamps in short ones")
    func mixedClamping() throws {
        let rule = RecurrenceRule(frequency: .monthly)
        let start = date(2026, 1, 31)
        let first = try #require(rule.next(after: start, from: start, calendar: calendar))
        let second = try #require(rule.next(after: first, from: start, calendar: calendar))
        #expect(monthDay(first) == (2, 28))
        #expect(monthDay(second) == (3, 31))
    }
}
