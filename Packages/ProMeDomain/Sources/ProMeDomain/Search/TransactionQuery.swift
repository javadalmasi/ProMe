import Foundation

/// A composable filter for the transaction list, built in the Domain layer
/// and translated to an NSPredicate by the data layer.
public struct TransactionQuery: Sendable {
    public enum SortKey: String, Sendable, CaseIterable, Codable {
        case date
        case amount
        case category
        case account
    }

    public var text: String
    public var scopeID: UUID?
    public var accountID: UUID?
    public var categoryID: UUID?
    public var kinds: Set<TransactionKind>
    public var startDate: Date?
    public var endDate: Date?
    public var minAmountMinor: Int64?
    public var maxAmountMinor: Int64?
    public var sort: SortKey
    public var ascending: Bool

    public init(
        text: String = "",
        scopeID: UUID? = nil,
        accountID: UUID? = nil,
        categoryID: UUID? = nil,
        kinds: Set<TransactionKind> = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        minAmountMinor: Int64? = nil,
        maxAmountMinor: Int64? = nil,
        sort: SortKey = .date,
        ascending: Bool = false
    ) {
        self.text = text
        self.scopeID = scopeID
        self.accountID = accountID
        self.categoryID = categoryID
        self.kinds = kinds
        self.startDate = startDate
        self.endDate = endDate
        self.minAmountMinor = minAmountMinor
        self.maxAmountMinor = maxAmountMinor
        self.sort = sort
        self.ascending = ascending
    }
}
