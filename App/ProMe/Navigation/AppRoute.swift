import Foundation

/// Top-level sidebar destinations, in display order. The index also drives
/// the ⌘1…⌘9 navigation shortcuts.
enum AppRoute: String, CaseIterable, Hashable, Sendable {
    // Life
    case dashboard
    case tasks
    case calendar
    case appointments
    case alertsActivities
    case notes
    case places
    // Money
    case transactions
    case accounts
    case transfers
    // Obligations & wealth
    case debts
    case loans
    case insurance
    case assets
    // Planning
    case categories
    case budgets
    case recurring
    // Insights
    case businesses
    case reports

    var title: String {
        switch self {
        case .dashboard: String(localized: "Dashboard")
        case .tasks: String(localized: "Daily Tasks")
        case .calendar: String(localized: "Calendar")
        case .appointments: String(localized: "Appointments")
        case .alertsActivities: String(localized: "Alerts & Activities")
        case .notes: String(localized: "Notes")
        case .places: String(localized: "Places")
        case .transactions: String(localized: "Transactions")
        case .accounts: String(localized: "Accounts")
        case .transfers: String(localized: "Transfers")
        case .debts: String(localized: "Debts & Receivables")
        case .loans: String(localized: "Loans")
        case .insurance: String(localized: "Insurance")
        case .assets: String(localized: "Assets")
        case .categories: String(localized: "Categories")
        case .budgets: String(localized: "Budgets")
        case .recurring: String(localized: "Recurring")
        case .businesses: String(localized: "Businesses")
        case .reports: String(localized: "Reports")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .appointments: "clock.badge.checkmark"
        case .alertsActivities: "bell.badge"
        case .notes: "note.text"
        case .places: "mappin.and.ellipse"
        case .transactions: "tray.full"
        case .accounts: "banknote"
        case .transfers: "arrow.left.arrow.right"
        case .debts: "person.crop.circle.badge.checkmark"
        case .loans: "bank.building"
        case .insurance: "shield.lefthalf.filled"
        case .assets: "house.and.flag.fill.2.crossed"
        case .categories: "tag"
        case .budgets: "gauge.with.needle"
        case .recurring: "arrow.clockwise.circle"
        case .businesses: "briefcase"
        case .reports: "chart.bar.doc.horizontal"
        }
    }
}

/// Sidebar grouping: personal life first, then the financial modules.
enum SidebarSection: String, CaseIterable, Sendable {
    case overview
    case life
    case money
    case obligationsWealth
    case planning
    case insights

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .life: String(localized: "My Life")
        case .money: String(localized: "Money")
        case .obligationsWealth: String(localized: "Obligations & Wealth")
        case .planning: String(localized: "Planning")
        case .insights: String(localized: "Insights")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .life: "person.crop.circle"
        case .money: "banknote"
        case .obligationsWealth: "safevault"
        case .planning: "calendar.badge.clock"
        case .insights: "chart.pie"
        }
    }

    var routes: [AppRoute] {
        switch self {
        case .overview: [.dashboard]
        case .life: [.tasks, .calendar, .appointments, .alertsActivities, .notes, .places]
        case .money: [.transactions, .accounts, .transfers]
        case .obligationsWealth: [.debts, .loans, .insurance, .assets]
        case .planning: [.categories, .budgets, .recurring]
        case .insights: [.businesses, .reports]
        }
    }
}
