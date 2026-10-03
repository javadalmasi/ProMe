import Foundation
import ProMeDomain

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cross-platform clipboard access (AppKit on macOS, UIKit elsewhere).
enum Clip {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// Formatting helpers for dates and amounts in the user's calendar and
/// digit style. Used by list rows and reports.
enum Format {
    static func amount(_ minor: Int64, code: String) -> String {
        let money = Money(minorUnits: minor, currency: .resolving(code))
        let base = money.formatted()
        return AppPreferences.digits == .persian ? persianDigits(base) : base
    }

    static func persianDigits(_ text: String) -> String {
        let latin = Array("0123456789")
        let persian = Array("۰۱۲۳۴۵۶۷۸۹")
        var result = ""
        for character in text {
            if let index = latin.firstIndex(of: character) {
                result.append(persian[index])
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        if AppPreferences.calendar == .persian {
            formatter.calendar = PersianCalendar(timeZone: .current).calendar
            formatter.locale = Locale(identifier: "fa_IR")
        } else {
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale.current
        }
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Time of day in the user's locale ("۱۴:۳۰").
    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let base = formatter.string(from: date)
        return AppPreferences.digits == .persian ? persianDigits(base) : base
    }

    /// Date and time combined for reminders and appointments.
    static func dateTimeText(_ date: Date) -> String {
        "\(dateText(date)) \(timeText(date))"
    }
}
