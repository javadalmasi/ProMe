import Foundation
import ProMeDomain
import Testing

@Suite("Persian calendar")
struct PersianCalendarTests {
    private let calendar = PersianCalendar(timeZone: TimeZone(secondsFromGMT: 0) ?? .current)

    private func gregorianDate(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = gregorian.date(from: components) else {
            throw ValidationError.invalidState("invalid gregorian date \(year)-\(month)-\(day)")
        }
        return date
    }

    @Test("2026-09-29 maps to 1405/07/07")
    func convertsCurrentDate() throws {
        #expect(calendar.formatted(try gregorianDate(2026, 9, 29)) == "1405/07/07")
    }

    @Test("Nowruz 1405 maps to 2026-03-21")
    func convertsNowruz() throws {
        #expect(calendar.formatted(try gregorianDate(2026, 3, 21)) == "1405/01/01")
    }

    @Test("Esfand 30 of leap year 1403 maps to 2025-03-20")
    func convertsLeapYearEnd() throws {
        #expect(calendar.formatted(try gregorianDate(2025, 3, 20)) == "1403/12/30")
    }

    @Test("Start of month lands on day 1")
    func startOfMonthIsDayOne() throws {
        let start = try #require(calendar.startOfMonth(for: try gregorianDate(2026, 9, 29)))
        #expect(calendar.formatted(start) == "1405/07/01")
    }

    @Test("Round-trips through date(from:)")
    func roundTrips() throws {
        let date = try #require(calendar.date(from: .init(year: 1405, month: 7, day: 7)))
        #expect(calendar.formatted(date) == "1405/07/07")
    }
}
