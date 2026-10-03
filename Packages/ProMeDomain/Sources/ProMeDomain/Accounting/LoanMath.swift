import Foundation

/// One planned installment of a loan: the principal/interest split plus
/// the clamped due date. Amounts are exact minor units.
public struct LoanInstallmentPlan: Sendable, Equatable {
    public let index: Int
    public let dueDate: Date
    public let principalMinor: Int64
    public let interestMinor: Int64

    public var totalMinor: Int64 { principalMinor + interestMinor }

    public init(index: Int, dueDate: Date, principalMinor: Int64, interestMinor: Int64) {
        self.index = index
        self.dueDate = dueDate
        self.principalMinor = principalMinor
        self.interestMinor = interestMinor
    }
}

/// Loan schedule math. Equal principal parts with flat interest over the
/// term, split evenly; the last installment absorbs rounding so the sum of
/// the parts is always exactly the agreed totals.
public enum LoanMath {
    public static func schedule(
        principalMinor: Int64,
        annualRatePercent: Decimal,
        termMonths: Int,
        startDate: Date,
        dueDay: Int,
        calendar: Calendar
    ) -> [LoanInstallmentPlan] {
        let count = max(1, termMonths)
        guard principalMinor > 0 else { return [] }

        var interestTotalMinor: Int64 = 0
        if annualRatePercent > 0 {
            let interest = Decimal(principalMinor) * annualRatePercent / 100
                * Decimal(count) / 12
            interestTotalMinor = Self.roundedMinor(interest)
        }

        let interestPer = interestTotalMinor / Int64(count)
        let interestRemainder = interestTotalMinor - interestPer * Int64(count)
        let principalPer = principalMinor / Int64(count)
        let principalRemainder = principalMinor - principalPer * Int64(count)

        var plans: [LoanInstallmentPlan] = []
        plans.reserveCapacity(count)
        for i in 1...count {
            let isLast = i == count
            let dueDate = clampedDueDate(start: startDate, months: i, dueDay: dueDay, calendar: calendar)
            plans.append(LoanInstallmentPlan(
                index: i,
                dueDate: dueDate,
                principalMinor: isLast ? principalPer + principalRemainder : principalPer,
                interestMinor: isLast ? interestPer + interestRemainder : interestPer
            ))
        }
        return plans
    }

    /// Installment i falls i months after the start, on `dueDay` clamped to
    /// the target month's length (Jan 31 start, dueDay 31 → Feb 28).
    public static func clampedDueDate(start: Date, months: Int, dueDay: Int, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        guard let startYear = components.year, let startMonth = components.month else {
            return start
        }
        let effectiveDay = dueDay >= 1 ? dueDay : (components.day ?? 1)
        let total = startYear * 12 + (startMonth - 1) + max(1, months)
        let year = total / 12
        let month = total % 12 + 1
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: first) else {
            return start
        }
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: min(effectiveDay, dayRange.count),
            hour: components.hour ?? 12,
            minute: components.minute ?? 0
        )) ?? start
    }

    private static func roundedMinor(_ value: Decimal) -> Int64 {
        let rounded = NSDecimalNumber(decimal: value).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )
        return rounded.int64Value
    }
}
