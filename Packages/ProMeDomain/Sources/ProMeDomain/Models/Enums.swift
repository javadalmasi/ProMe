import Foundation

/// The two kinds of financial scope: the user's private finances and each
/// of their independent businesses.
public enum ScopeKind: String, Sendable, CaseIterable, Codable {
    case personal
    case business
}

public enum AccountType: String, Sendable, CaseIterable, Codable {
    case current
    case savings
    case shortTermDeposit
    case longTermDeposit
    case card
    case foreignCurrency
    case cash
    case wallet
    case credit
    case other
}

public enum AccountStatus: String, Sendable, CaseIterable, Codable {
    case active
    case archived
}

public enum CategoryKind: String, Sendable, CaseIterable, Codable {
    case income
    case expense
}

public enum LedgerAccountType: String, Sendable, CaseIterable, Codable {
    case asset
    case liability
    case equity
    case income
    case expense
}

public enum LedgerDirection: String, Sendable, CaseIterable, Codable {
    case debit
    case credit
}

/// The financial event that produced a journal. Posting rules in the
/// accounting engine map each of these to a balanced set of ledger lines.
public enum JournalKind: String, Sendable, CaseIterable, Codable {
    case income
    case expense
    case transfer
    case refund
    case adjustment
    case ownerContribution
    case ownerWithdrawal
    case loanReceived
    case loanInstallment
    case debtLent
    case debtRepaid
    case debtBorrowed
    case debtSettled
    case assetPurchase
    case assetSale
    case insurancePremium
    case currencyConversion
    case correction
}

public enum TransactionKind: String, Sendable, CaseIterable, Codable {
    case income
    case expense
    case transfer
    case ownerContribution
    case ownerWithdrawal
    case refund
    case adjustment
    case other

    public var isTransferLike: Bool {
        switch self {
        case .transfer, .ownerContribution, .ownerWithdrawal: return true
        default: return false
        }
    }
}

public enum AttachmentKind: String, Sendable, CaseIterable, Codable {
    case image
    case pdf
    case document
    case other
}

public enum CounterpartyKind: String, Sendable, CaseIterable, Codable {
    case person
    case business
}

public enum AssetType: String, Sendable, CaseIterable, Codable {
    case vehicle
    case property
    case electronics
    case equipment
    case investment
    case jewelry
    case other
}

public enum AssetStatus: String, Sendable, Codable {
    case owned
    case sold
}

public enum CalendarPreference: String, Sendable, CaseIterable, Codable {
    case gregorian
    case persian
}

public enum DigitStyle: String, Sendable, CaseIterable, Codable {
    case latin
    case persian
}

public enum ThemePreference: String, Sendable, CaseIterable, Codable {
    case system
    case light
    case dark
}
