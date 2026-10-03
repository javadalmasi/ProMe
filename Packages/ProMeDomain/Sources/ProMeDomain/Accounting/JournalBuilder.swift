import Foundation

/// A single ledger line produced by a posting rule.
public struct PostingLine: Hashable, Sendable {
    public let ledgerAccountCode: String
    public let direction: LedgerDirection
    public let money: Money

    public init(ledgerAccountCode: String, direction: LedgerDirection, money: Money) {
        self.ledgerAccountCode = ledgerAccountCode
        self.direction = direction
        self.money = money
    }
}

/// The immutable output of the accounting engine for one financial event:
/// a journal whose debit and credit totals balance per currency.
public struct BalancedJournal: Hashable, Sendable {
    public let kind: JournalKind
    public let date: Date
    public let memo: String?
    public let lines: [PostingLine]
}

/// Turns financial events into balanced journals. This is the only place in
/// the app allowed to invent ledger lines, which is what structurally
/// guarantees that transfers, owner contributions and loans never leak
/// into income or expense reports.
public enum JournalBuilder {
    /// Validates and assembles a journal. Throws when the lines do not
    /// balance per currency or are too few to represent a real event.
    public static func build(
        kind: JournalKind,
        date: Date,
        memo: String?,
        lines: [PostingLine]
    ) throws -> BalancedJournal {
        guard lines.count >= 2 else { throw AccountingError.emptyJournal }

        var debitTotals: [String: Int64] = [:]
        var creditTotals: [String: Int64] = [:]

        for line in lines {
            switch line.direction {
            case .debit:
                debitTotals[line.money.currency.code] = try accumulate(
                    debitTotals[line.money.currency.code],
                    line.money.minorUnits
                )
            case .credit:
                creditTotals[line.money.currency.code] = try accumulate(
                    creditTotals[line.money.currency.code],
                    line.money.minorUnits
                )
            }
        }

        // Cross-currency journals (e.g. an FX transfer with a realized
        // gain/loss leg) arrive with the transfer service in a later
        // milestone; for now a journal must be single-currency.
        let currencies = Set(debitTotals.keys).union(creditTotals.keys)
        guard currencies.count == 1, let code = currencies.first else {
            throw AccountingError.mixedCurrencyJournal
        }
        guard let credit = creditTotals[code], credit == debitTotals[code] ?? 0 else {
            throw AccountingError.unbalancedJournal(
                detail: "currency \(code): debit \(debitTotals[code] ?? 0) vs credit \(creditTotals[code] ?? 0)"
            )
        }

        return BalancedJournal(kind: kind, date: date, memo: memo, lines: lines)
    }

    private static func accumulate(_ current: Int64?, _ addition: Int64) throws -> Int64 {
        let (sum, overflow) = (current ?? 0).addingReportingOverflow(addition)
        guard !overflow else { throw AccountingError.amountOverflow }
        return sum
    }
}
