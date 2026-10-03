import Foundation

/// Receivable (someone owes me) vs payable (I owe someone).
public enum DebtKind: String, Sendable, CaseIterable, Codable {
    case receivable
    case payable
}

public enum DebtStatus: String, Sendable, Codable {
    case open
    case settled
}

public enum LoanStatus: String, Sendable, Codable {
    case active
    case settled
}

public enum InstallmentStatus: String, Sendable, Codable {
    case pending
    case paid
}

public enum InsuranceType: String, Sendable, CaseIterable, Codable {
    case socialSecurity
    case supplementary
    case car
    case life
    case health
    case other
}

public enum PaymentPeriod: String, Sendable, CaseIterable, Codable {
    case monthly
    case quarterly
    case yearly

    public var recurrence: RecurrenceRule {
        switch self {
        case .monthly: RecurrenceRule(frequency: .monthly)
        case .quarterly: RecurrenceRule(frequency: .quarterly)
        case .yearly: RecurrenceRule(frequency: .yearly)
        }
    }
}
