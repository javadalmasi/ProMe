import Foundation

/// Factory for the ledger account codes the posting rules rely on.
/// Codes are stable, derived identifiers; the human readable name lives in
/// the store. Every posting line must reference one of these codes so that
/// reports can be traced back to their source object.
public enum ChartOfAccounts {
    public static func assetAccountCode(forAccountID id: UUID) -> String {
        "AST.\(id.uuidString)"
    }

    public static func incomeCategoryCode(forCategoryID id: UUID) -> String {
        "INC.\(id.uuidString)"
    }

    public static func expenseCategoryCode(forCategoryID id: UUID) -> String {
        "EXP.\(id.uuidString)"
    }

    public static func receivableCode(forCounterpartyID id: UUID) -> String {
        "RCV.\(id.uuidString)"
    }

    public static func payableCode(forCounterpartyID id: UUID) -> String {
        "PAY.\(id.uuidString)"
    }

    public static func loanLiabilityCode(forLoanID id: UUID) -> String {
        "LOAN.\(id.uuidString)"
    }

    public static func ownerContributionCode(forScopeID id: UUID) -> String {
        "EQC.\(id.uuidString)"
    }

    public static func ownerWithdrawalCode(forScopeID id: UUID) -> String {
        "EQW.\(id.uuidString)"
    }

    public static func fixedAssetCode(forAssetID id: UUID) -> String {
        "FIX.\(id.uuidString)"
    }

    public static let assetGainCode = "INC.SALE"
    public static let assetLossCode = "EXP.SALE"
    public static let fxGainCode = "INC.FX"
    public static let fxLossCode = "EXP.FX"
    public static let interestExpenseCode = "EXP.INT"
    public static let personalEquityCode = "EQ.PERSONAL"
}
