import Foundation

/// Domain-level validation failures. The UI layer maps these to localized,
/// human readable messages; business rules never crash the app.
public enum ValidationError: Error, Sendable, Equatable {
    case missingField(String)
    case invalidAmount(String)
    case duplicateName(String)
    case invalidState(String)
}

/// Errors raised by the accounting engine and money math.
public enum AccountingError: Error, Sendable, Equatable {
    case unbalancedJournal(detail: String)
    case emptyJournal
    case mixedCurrencyJournal
    case unknownLedgerAccount(code: String)
    case currencyMismatch(expected: String, actual: String)
    case amountOverflow
    case invalidExchangeRate
}

/// Errors raised by the persistence layer.
public enum DatabaseError: Error, Sendable, Equatable {
    case modelNotFound
    case storeLoadFailed(String)
    case saveFailed(String)
}

extension ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingField(let field):
            String(localized: "The field “\(field)” is required.")
        case .invalidAmount(let detail):
            String(localized: "The amount is not valid. \(detail)")
        case .duplicateName(let name):
            String(localized: "An item named “\(name)” already exists.")
        case .invalidState(let detail):
            String(localized: "This operation is not allowed. \(detail)")
        }
    }
}

extension AccountingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unbalancedJournal(let detail):
            String(localized: "The accounting entry is not balanced. \(detail)")
        case .emptyJournal:
            String(localized: "An accounting entry needs at least two lines.")
        case .mixedCurrencyJournal:
            String(localized: "A single accounting entry cannot mix currencies.")
        case .unknownLedgerAccount(let code):
            String(localized: "The accounting account \(code) could not be found.")
        case .currencyMismatch(let expected, let actual):
            String(localized: "Currencies do not match: expected \(expected) but got \(actual).")
        case .amountOverflow:
            String(localized: "The amount is too large.")
        case .invalidExchangeRate:
            String(localized: "The exchange rate must be greater than zero.")
        }
    }
}

extension DatabaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            String(localized: "The database model could not be loaded.")
        case .storeLoadFailed(let detail):
            String(localized: "The database could not be opened. \(detail)")
        case .saveFailed(let detail):
            String(localized: "Saving changes failed. \(detail)")
        }
    }
}
