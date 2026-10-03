import CoreData
import ProMeData
import ProMeDomain
import SwiftUI

/// Sheets that can be opened from anywhere via the File menu shortcuts.
enum GlobalSheet: String, Identifiable {
    case transfer
    case account
    case category
    case business
    case debt
    case loan
    case insurance
    case task
    case appointment
    case note
    case alert

    var id: String { rawValue }
}

/// Which financial scope the whole UI is currently filtered to.
enum ScopeSelection: Hashable {
    case all
    case scope(UUID)
}

@MainActor
@Observable
final class AppModel {
    /// All long-lived data services, built once around the store.
    struct Services {
        let scopes: ScopeRepository
        let accounts: AccountRepository
        let categories: CategoryRepository
        let posting: PostingService
        let transactions: TransactionRepository
        let aggregates: AggregateQueries
        let recurring: RecurringService
        let budgets: BudgetService
        let backup: BackupService
        let debts: DebtService
        let loans: LoanService
        let insurances: InsuranceService
        let assets: AssetService
        let reconciliation: ReconciliationService
        let importService: ImportService
        let categorization: CategorizationService
        // Personal life
        let tasks: TaskService
        let activities: ActivityService
        let alerts: AlertService
        let appointments: AppointmentService
        let notes: NoteService
        let places: PlaceService
        let sync: SyncService
    }

    private(set) var persistence: PersistenceController?
    private(set) var services: Services?
    private(set) var launchError: (any Error)?

    var selectedRoute: AppRoute = .dashboard
    var scopeSelection: ScopeSelection = .all
    var quickEntryPresented = false
    private(set) var scopesList: [FinancialScopeMO] = []

    /// Global quick-access state (File-menu shortcuts and help).
    var presentedSheet: GlobalSheet?
    var showShortcuts = false
    /// In-app settings (iOS has no Settings scene).
    var showSettings = false

    /// Bumped whenever data changes through a global sheet; screens key
    /// their fetch tasks on it so lists refresh without manual reloads.
    var dataEpoch = 0

    /// Bumped by ⌘F to move focus into the transaction search field.
    var focusSearchToken = 0

    func bumpData() {
        dataEpoch += 1
    }

    init() {
        // First launch defaults to Persian; a user choice (Settings →
        // General → App Language) overrides it, including "system".
        if UserDefaults.standard.string(forKey: "appLanguage") == nil {
            UserDefaults.standard.register(defaults: ["AppleLanguages": ["fa"]])
        }
        do {
            let persistence = try PersistenceController()
            self.persistence = persistence
            self.launchError = nil

            let scopes = ScopeRepository(controller: persistence)
            let accounts = AccountRepository(controller: persistence)
            let categories = CategoryRepository(controller: persistence)
            let posting = PostingService(controller: persistence)
            let aggregates = AggregateQueries(controller: persistence)
            self.services = Services(
                scopes: scopes,
                accounts: accounts,
                categories: categories,
                posting: posting,
                transactions: TransactionRepository(controller: persistence),
                aggregates: aggregates,
                recurring: RecurringService(controller: persistence, posting: posting),
                budgets: BudgetService(controller: persistence, aggregates: aggregates),
                backup: BackupService(controller: persistence),
                debts: DebtService(controller: persistence),
                loans: LoanService(controller: persistence),
                insurances: InsuranceService(controller: persistence, recurring: RecurringService(controller: persistence, posting: posting)),
                assets: AssetService(controller: persistence),
                reconciliation: ReconciliationService(controller: persistence),
                importService: ImportService(controller: persistence, posting: posting),
                categorization: CategorizationService(controller: persistence),
                tasks: TaskService(controller: persistence),
                activities: ActivityService(controller: persistence),
                alerts: AlertService(controller: persistence),
                appointments: AppointmentService(controller: persistence),
                notes: NoteService(controller: persistence),
                places: PlaceService(controller: persistence),
                sync: SyncService(controller: persistence)
            )
            try SeedService(controller: persistence).runIfNeeded()
            scopesList = try scopes.allScopes()
            try? services?.recurring.postDue()
            persistence.pruneDeletionLog()
            NotificationsService.refreshReminders(appModel: self)
        } catch {
            self.persistence = nil
            self.services = nil
            self.launchError = error
            ProMeLog.record(error, context: "launch")
        }
    }

    /// The concrete scope the UI filters by, or nil for "All".
    var activeScope: FinancialScopeMO? {
        guard case .scope(let id) = scopeSelection else { return nil }
        return scopesList.first { $0.id == id }
    }

    var personalScope: FinancialScopeMO? {
        scopesList.first { $0.kind == .personal }
    }

    func reloadScopes() {
        guard let services else { return }
        scopesList = (try? services.scopes.allScopes()) ?? []
    }

    // MARK: - Undo support

    /// Everything needed to re-post a deleted transaction for Undo.
    struct UndoSnapshot {
        let kind: TransactionKind
        let amountMinor: Int64
        let date: Date
        let memo: String?
        let accountID: NSManagedObjectID?
        let fromID: NSManagedObjectID?
        let toID: NSManagedObjectID?
        let categoryID: NSManagedObjectID?
        let scopeID: NSManagedObjectID?
    }

    func makeSnapshot(of transaction: TransactionMO) -> UndoSnapshot {
        UndoSnapshot(
            kind: transaction.kind,
            amountMinor: transaction.amountMinor,
            date: transaction.postedAt,
            memo: transaction.memo,
            accountID: transaction.account?.objectID,
            fromID: transaction.fromAccount?.objectID,
            toID: transaction.toAccount?.objectID,
            categoryID: transaction.category?.objectID,
            scopeID: transaction.scope?.objectID
        )
    }

    /// Re-posts a deleted transaction. Returns false when related objects
    /// no longer exist.
    func undoDelete(_ snapshot: UndoSnapshot) -> Bool {
        guard let services else { return false }
        let context = persistence?.container.viewContext
        func object(_ id: NSManagedObjectID?) -> NSManagedObject? {
            guard let id, let context else { return nil }
            let object = context.object(with: id)
            return object.isFault && object.managedObjectContext == nil ? nil : object
        }
        guard let scope = object(snapshot.scopeID) as? FinancialScopeMO else { return false }
        switch snapshot.kind {
        case .income:
            guard let account = object(snapshot.accountID) as? MoneyAccountMO,
                  let category = object(snapshot.categoryID) as? CategoryMO else { return false }
            return (try? services.posting.postIncome(
                scope: scope, account: account, category: category,
                amountMinor: snapshot.amountMinor, date: snapshot.date, memo: snapshot.memo
            )) != nil
        case .expense:
            guard let account = object(snapshot.accountID) as? MoneyAccountMO,
                  let category = object(snapshot.categoryID) as? CategoryMO else { return false }
            return (try? services.posting.postExpense(
                scope: scope, account: account, category: category,
                amountMinor: snapshot.amountMinor, date: snapshot.date, memo: snapshot.memo
            )) != nil
        case .transfer:
            guard let from = object(snapshot.fromID) as? MoneyAccountMO,
                  let to = object(snapshot.toID) as? MoneyAccountMO else { return false }
            return (try? services.posting.postTransfer(
                from: from, to: to, amountMinor: snapshot.amountMinor,
                date: snapshot.date, memo: snapshot.memo
            )) != nil
        case .ownerContribution:
            guard let from = object(snapshot.fromID) as? MoneyAccountMO,
                  let to = object(snapshot.toID) as? MoneyAccountMO else { return false }
            return (try? services.posting.postOwnerContribution(
                from: from, to: to, amountMinor: snapshot.amountMinor,
                date: snapshot.date, memo: snapshot.memo
            )) != nil
        case .ownerWithdrawal:
            guard let from = object(snapshot.fromID) as? MoneyAccountMO,
                  let to = object(snapshot.toID) as? MoneyAccountMO else { return false }
            return (try? services.posting.postOwnerWithdrawal(
                from: from, to: to, amountMinor: snapshot.amountMinor,
                date: snapshot.date, memo: snapshot.memo
            )) != nil
        default:
            return false
        }
    }
}

/// App-wide preferences kept in UserDefaults (small values, no schema).
enum AppPreferences {
    static var calendar: CalendarPreference {
        CalendarPreference(rawValue: UserDefaults.standard.string(forKey: "calendarPreference") ?? "") ?? .persian
    }

    static var digits: DigitStyle {
        DigitStyle(rawValue: UserDefaults.standard.string(forKey: "digitStyle") ?? "") ?? .latin
    }

    static var baseCurrency: Currency {
        Currency.resolving(UserDefaults.standard.string(forKey: "baseCurrency") ?? "IRR")
    }
}

/// Display helpers live in `Format.swift`; this file owns state, services
/// and type display names.

extension TransactionKind {
    var displayName: String {
        switch self {
        case .income: String(localized: "Income")
        case .expense: String(localized: "Expense")
        case .transfer: String(localized: "Transfer")
        case .ownerContribution: String(localized: "Owner Contribution")
        case .ownerWithdrawal: String(localized: "Owner Withdrawal")
        case .refund: String(localized: "Refund")
        case .adjustment: String(localized: "Adjustment")
        case .other: String(localized: "Other")
        }
    }

    var systemImage: String {
        switch self {
        case .income: "arrow.down.circle.fill"
        case .expense: "arrow.up.circle.fill"
        case .transfer, .ownerContribution, .ownerWithdrawal: "arrow.left.arrow.right.circle.fill"
        case .refund: "arrow.uturn.left.circle.fill"
        case .adjustment: "slider.horizontal.3"
        case .other: "circle.dashed"
        }
    }
}

extension AccountType {
    var displayName: String {
        switch self {
        case .current: String(localized: "Current")
        case .savings: String(localized: "Savings")
        case .shortTermDeposit: String(localized: "Short-term Deposit")
        case .longTermDeposit: String(localized: "Long-term Deposit")
        case .card: String(localized: "Card")
        case .foreignCurrency: String(localized: "Foreign Currency")
        case .cash: String(localized: "Cash")
        case .wallet: String(localized: "Wallet")
        case .credit: String(localized: "Credit")
        case .other: String(localized: "Other")
        }
    }

    var systemImage: String {
        switch self {
        case .current: "building.columns"
        case .savings, .shortTermDeposit, .longTermDeposit: "pie.chart"
        case .card: "creditcard"
        case .foreignCurrency: "dollarsign.circle"
        case .cash: "banknote"
        case .wallet: "wallet.pass"
        case .credit: "creditcard.and.123"
        case .other: "questionmark.folder"
        }
    }
}

extension RecurrenceFrequency {
    var displayName: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Quarterly")
        case .yearly: String(localized: "Yearly")
        }
    }
}
