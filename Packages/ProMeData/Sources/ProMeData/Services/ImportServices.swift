import CoreData
import Foundation
import ProMeDomain

/// Bank-statement CSV import: parse, map columns, detect duplicates,
/// and post every row through the normal posting service.
@MainActor
public final class ImportService {
    private let controller: PersistenceController
    private let posting: PostingService
    public init(controller: PersistenceController, posting: PostingService) {
        self.controller = controller
        self.posting = posting
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    /// Column assignment inside the CSV.
    public struct Mapping: Sendable, Equatable {
        public var dateColumn: Int
        public var descriptionColumn: Int?
        public var amountColumn: Int?
        public var debitColumn: Int?
        public var creditColumn: Int?
        public var referenceColumn: Int?
        public var hasHeader: Bool

        public init(
            dateColumn: Int = 0,
            descriptionColumn: Int? = 1,
            amountColumn: Int? = 2,
            debitColumn: Int? = nil,
            creditColumn: Int? = nil,
            referenceColumn: Int? = nil,
            hasHeader: Bool = true
        ) {
            self.dateColumn = dateColumn
            self.descriptionColumn = descriptionColumn
            self.amountColumn = amountColumn
            self.debitColumn = debitColumn
            self.creditColumn = creditColumn
            self.referenceColumn = referenceColumn
            self.hasHeader = hasHeader
        }
    }

    public struct DraftRow: Identifiable, Equatable {
        public var id = UUID()
        public var date: Date
        public var amountMinor: Int64  // positive = money in, negative = money out
        public var memo: String?
        public var referenceNo: String?
        public var isDuplicate: Bool = false
    }

    public struct ImportResult: Equatable {
        public var imported: Int
        public var skippedDuplicates: Int
        public var failedRows: Int
    }

    /// Date formats tried in order; bank CSVs vary widely.
    public static let dateFormats = ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "dd.MM.yyyy", "yyyy-MM-dd'T'HH:mm:ss", "yyyyMMdd"]

    public static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    public static func parseAmount(_ raw: String) -> Int64? {
        MoneyInput.parseDecimal(raw).map { decimal in
            let money = Money(majorUnits: decimal, currency: .irr)
            return money.minorUnits
        }
    }

    /// Builds draft rows from parsed CSV cells. Rows without a valid date
    /// or amount are dropped.
    public func draftRows(
        cells: [[String]],
        mapping: Mapping,
        currency: Currency
    ) throws -> [DraftRow] {
        let body = mapping.hasHeader ? Array(cells.dropFirst()) : cells
        var drafts: [DraftRow] = []
        for line in body {
            guard mapping.dateColumn < line.count else { continue }
            guard let date = Self.parseDate(line[mapping.dateColumn]) else { continue }

            var amountMinor: Int64?
            if let amountColumn = mapping.amountColumn, amountColumn < line.count {
                amountMinor = Self.parseAmount(line[amountColumn])
            } else if let debitColumn = mapping.debitColumn, let creditColumn = mapping.creditColumn {
                let debit = debitColumn < line.count ? Self.parseAmount(line[debitColumn]) ?? 0 : 0
                let credit = creditColumn < line.count ? Self.parseAmount(line[creditColumn]) ?? 0 : 0
                if debit != 0 || credit != 0 {
                    amountMinor = credit - debit
                }
            }
            guard let amount = amountMinor, amount != 0 else { continue }

            var memo: String?
            if let descriptionColumn = mapping.descriptionColumn, descriptionColumn < line.count {
                let raw = line[descriptionColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                memo = raw.isEmpty ? nil : raw
            }
            var reference: String?
            if let referenceColumn = mapping.referenceColumn, referenceColumn < line.count {
                let raw = line[referenceColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                reference = raw.isEmpty ? nil : raw
            }
            drafts.append(DraftRow(date: date, amountMinor: amount, memo: memo, referenceNo: reference))
        }
        return drafts
    }

    /// Flags drafts that look like existing transactions for the account:
    /// same amount and a posted date within ±2 days.
    public func flagDuplicates(account: MoneyAccountMO, drafts: inout [DraftRow]) throws {
        let request = TransactionMO.fetchRequest()
        request.predicate = NSPredicate(
            format: "(account == %@ OR fromAccount == %@ OR toAccount == %@)",
            account, account, account
        )
        request.sortDescriptors = [NSSortDescriptor(key: "postedAt", ascending: false)]
        request.fetchLimit = 5000
        let existing = try context.fetch(request)

        for index in drafts.indices {
            let draft = drafts[index]
            let expectedKind: TransactionKind = draft.amountMinor > 0 ? .income : .expense
            let expectedAmount = draft.amountMinor < 0 ? -draft.amountMinor : draft.amountMinor
            let isDuplicate = existing.contains { transaction in
                transaction.kind == expectedKind
                    && transaction.amountMinor == expectedAmount
                    && abs(transaction.postedAt.timeIntervalSince(draft.date)) < 2 * 86_400
            }
            drafts[index].isDuplicate = isDuplicate
        }
    }

    /// Posts the drafts. Positive amounts become income, negative expense,
    /// all under the chosen category. Duplicate handling per policy.
    public func `import`(
        drafts: [DraftRow],
        scope: FinancialScopeMO,
        account: MoneyAccountMO,
        incomeCategory: CategoryMO?,
        expenseCategory: CategoryMO,
        skipDuplicates: Bool
    ) throws -> ImportResult {
        var result = ImportResult(imported: 0, skippedDuplicates: 0, failedRows: 0)
        for draft in drafts {
            if draft.isDuplicate && skipDuplicates {
                result.skippedDuplicates += 1
                continue
            }
            do {
                if draft.amountMinor > 0 {
                    guard let incomeCategory else { throw ValidationError.missingField("income category") }
                    _ = try posting.postIncome(
                        scope: scope, account: account, category: incomeCategory,
                        amountMinor: draft.amountMinor, date: draft.date,
                        memo: draft.memo, referenceNo: draft.referenceNo
                    )
                } else {
                    _ = try posting.postExpense(
                        scope: scope, account: account, category: expenseCategory,
                        amountMinor: -draft.amountMinor, date: draft.date,
                        memo: draft.memo, referenceNo: draft.referenceNo
                    )
                }
                result.imported += 1
            } catch {
                result.failedRows += 1
            }
        }
        return result
    }
}

/// Learns from history: the most common category among past transactions
/// whose memo matches the typed description. The user always keeps the
/// final say — this only pre-fills an empty picker.
@MainActor
public final class CategorizationService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public func suggestCategory(kind: CategoryKind, memo: String) throws -> CategoryMO? {
        let token = Self.significantToken(from: memo)
        guard let token else { return nil }

        let request = TransactionMO.fetchRequest()
        request.predicate = NSPredicate(
            format: "kindRaw == %@ AND memo CONTAINS[cd] %@ AND category != nil",
            kind.rawValue, token
        )
        request.sortDescriptors = [NSSortDescriptor(key: "postedAt", ascending: false)]
        request.fetchLimit = 50
        let matches = try context.fetch(request)
        guard matches.count >= 2 else { return nil }

        var counts: [NSManagedObjectID: (count: Int, category: CategoryMO)] = [:]
        for transaction in matches {
            guard let category = transaction.category else { continue }
            let entry = counts[category.objectID] ?? (0, category)
            counts[category.objectID] = (entry.count + 1, category)
        }
        return counts.values.max { $0.count < $1.count }?.category
    }

    /// The longest word with at least three letters/digits — good enough
    /// to identify payees like "Snapp" or "Digikala".
    static func significantToken(from memo: String) -> String? {
        let words = memo
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "," })
            .map { String($0.filter { $0.isLetter || $0.isNumber }) }
            .filter { $0.count >= 3 }
        return words.max { $0.count < $1.count }
    }
}
