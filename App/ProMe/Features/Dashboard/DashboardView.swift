import Charts
import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// The main overview: net worth, monthly flow, charts with drill-down,
/// account cards, recent activity, upcoming payments and budget status.
struct DashboardView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = DashboardModel()
    @State private var life = LifeTodaySummary()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                lifeRow
                if model.isEmpty {
                    EmptyStateView(
                        systemImage: "square.grid.2x2",
                        title: String(localized: "Welcome to ProMe"),
                        detail: String(localized: "Add an account and record your first transaction to see the dashboard come alive.")
                    )
                } else {
                    summaryRow
                    chartsRow
                    if !model.accountCards.isEmpty { accountsSection }
                    if !model.budgetRows.isEmpty { budgetsSection }
                    bottomRow
                }
            }
            .padding(20)
        }
        .navigationTitle(String(localized: "Dashboard"))
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") {
            model.reload(appModel: appModel)
            reloadLife()
        }
        .onAppear {
            model.reload(appModel: appModel)
            reloadLife()
        }
        .sheet(item: $model.drillDown) { selection in
            DrillDownView(selection: selection)
                .frame(minWidth: 620, minHeight: 420)
        }
    }

    // MARK: - Life today

    /// The personal-life pulse: today's tasks, next appointment and
    /// upcoming alerts — ProMe is a personal suite, not only accounting.
    @ViewBuilder
    private var lifeRow: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(String(localized: "My Day"), systemImage: "sparkles")
                        .font(.appHeadline)
                    Spacer()
                    Text(Format.dateText(.now))
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                if life.isEmpty {
                    Text(String(localized: "No tasks, appointments or alerts for today. Enjoy!"))
                        .font(.appCallout)
                        .foregroundStyle(.secondary)
                } else {
                    if !life.openTasks.isEmpty {
                        ForEach(life.openTasks.prefix(4), id: \.objectID) { task in
                            Button {
                                _ = try? appModel.services?.tasks.complete(task)
                                reloadLife()
                                appModel.bumpData()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "circle")
                                        .font(.appCaption)
                                        .foregroundStyle(Color.accentColor)
                                    Text(task.title).font(.appCallout)
                                        .strikethrough(false)
                                    Spacer()
                                    if task.priority == .urgent || task.priority == .high {
                                        Image(systemName: task.priority == .urgent ? "exclamationmark.2" : "exclamationmark")
                                            .font(.appCaption2)
                                            .foregroundStyle(task.priority == .urgent ? ProMeColor.expense : Color.orange)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        if life.doneCount > 0 {
                            Text(String(localized: "\(life.doneCount) task(s) completed today 🎉"))
                                .font(.appCaption)
                                .foregroundStyle(ProMeColor.income)
                        }
                    }
                    if let appointment = life.nextAppointment {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.appCaption)
                                .foregroundStyle(Color.orange)
                            Text(appointment.title).font(.appCallout)
                            Text(appointment.isAllDay
                                ? String(localized: "All day")
                                : Format.timeText(appointment.startsAt))
                                .font(.appCaption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.dateText(appointment.startsAt))
                                .font(.appCaption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if life.alertCount > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge")
                                .font(.appCaption)
                                .foregroundStyle(ProMeColor.expense)
                            Text(String(localized: "\(life.alertCount) active alert(s)"))
                                .font(.appCallout)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func reloadLife() {
        guard let services = appModel.services else { return }
        let open = ((try? services.tasks.today()) ?? []).filter { !$0.isDone }
        let done = ((try? services.tasks.today()) ?? []).filter(\.isDone)
        let next = ((try? services.appointments.upcoming(withinDays: 7)) ?? []).first
        let alerts = (try? services.alerts.active()) ?? []
        life = LifeTodaySummary(openTasks: open, doneCount: done.count, nextAppointment: next, alertCount: alerts.count)
    }

    // MARK: - Sections

    private var summaryRow: some View {
        let flowAbsolute = model.cashFlowMonth < 0 ? 0 &- model.cashFlowMonth : model.cashFlowMonth
        let flowText = (model.cashFlowMonth >= 0 ? "+" : "−") + Format.amount(flowAbsolute, code: model.baseCode)
        let flowColor: Color = model.cashFlowMonth >= 0 ? ProMeColor.income : ProMeColor.expense
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            SummaryCard(title: String(localized: "Net Worth"), value: model.baseText(model.netWorth), accent: .primary)
            SummaryCard(title: String(localized: "Cash"), value: model.baseText(model.cash), accent: .primary)
            SummaryCard(title: String(localized: "Income This Month"), value: "+" + model.baseText(model.incomeMonth), accent: ProMeColor.income)
            SummaryCard(title: String(localized: "Expense This Month"), value: "−" + model.baseText(model.expenseMonth), accent: ProMeColor.expense)
            SummaryCard(title: String(localized: "Cash Flow"), value: flowText, accent: flowColor)
        }
    }

    private var chartsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            if !model.monthlyBars.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Income vs Expense")).font(.appHeadline)
                        Chart {
                            ForEach(model.monthlyBars, id: \.label) { bar in
                                BarMark(
                                    x: .value(String(localized: "Month"), bar.label),
                                    y: .value(String(localized: "Amount"), Double(bar.income))
                                )
                                .foregroundStyle(ProMeColor.income)
                                BarMark(
                                    x: .value(String(localized: "Month"), bar.label),
                                    y: .value(String(localized: "Amount"), Double(bar.expense))
                                )
                                .foregroundStyle(ProMeColor.expense)
                            }
                        }
                        .chartForegroundStyleScale([
                            String(localized: "Income"): ProMeColor.income,
                            String(localized: "Expense"): ProMeColor.expense,
                        ])
                        .frame(height: 190)
                    }
                }
            }

            if !model.categorySlices.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Expense by Category")).font(.appHeadline)
                        Chart(model.categorySlices, id: \.name) { slice in
                            SectorMark(
                                angle: .value(String(localized: "Amount"), Double(slice.minor)),
                                innerRadius: .ratio(0.55),
                                angularInset: 1
                            )
                            .foregroundStyle(by: .value(String(localized: "Category"), slice.name))
                            .cornerRadius(3)
                        }
                        .chartLegend(.hidden)
                        .frame(height: 190)
                        LegendList(slices: model.categorySlices) { slice in
                            model.drillDown = DrillDownSelection(categoryName: slice.name, categoryID: slice.categoryID)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Accounts")).font(.appHeadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(model.accountCards, id: \.account.objectID) { card in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: card.account.type.systemImage)
                                .foregroundStyle(ProMeColor.transfer)
                            Text(card.account.name).font(.appCallout.weight(.medium)).lineLimit(1)
                        }
                        Text(Format.amount(card.balance, code: card.account.currencyCode))
                            .font(.appBody.monospacedDigit().weight(.semibold))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: ProMeSpacing.cardCorner).fill(.background.secondary))
                    .onTapGesture { model.drillDown = DrillDownSelection(accountID: card.account.id, accountName: card.account.name) }
                }
            }
        }
    }

    @ViewBuilder
    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Budgets")).font(.appHeadline)
            Card {
                VStack(spacing: 10) {
                    ForEach(model.budgetRows) { row in
                        HStack {
                            Text(row.entry.category?.name ?? "—").font(.appCallout).frame(width: 130, alignment: .leading)
                            ProgressView(value: min(row.fractionUsed, 1.0))
                                .progressViewStyle(.linear)
                                .tint(row.fractionUsed > 1 ? ProMeColor.expense : (row.fractionUsed > 0.8 ? .orange : ProMeColor.income))
                            Text("\(Int(row.fractionUsed * 100))%")
                                .font(.appCaption.monospacedDigit())
                                .foregroundStyle(row.fractionUsed > 1 ? ProMeColor.expense : .secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        if row.fractionUsed > 1 {
                            Label(String(localized: "Over budget"), systemImage: "exclamationmark.triangle.fill")
                                .font(.appCaption)
                                .foregroundStyle(ProMeColor.expense)
                        }
                    }
                }
            }
        }
    }

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Recent Transactions")).font(.appHeadline)
                    ForEach(model.recent, id: \.objectID) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Upcoming Payments")).font(.appHeadline)
                    if model.upcoming.isEmpty {
                        Text(String(localized: "Nothing due in the next 30 days."))
                            .font(.appCallout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.upcoming, id: \.objectID) { recurring in
                        HStack {
                            Image(systemName: recurring.kind.systemImage)
                                .foregroundStyle(ProMeColor.transfer)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recurring.memo ?? recurring.category?.name ?? recurring.kind.displayName)
                                    .font(.appCallout.weight(.medium))
                                Text(Format.dateText(recurring.nextDueAt))
                                    .font(.appCaption)
                                    .foregroundStyle(recurring.nextDueAt.timeIntervalSinceNow < 3 * 86400 ? ProMeColor.expense : .secondary)
                            }
                            Spacer()
                            Text(Format.amount(recurring.amountMinor, code: recurring.currencyCode))
                                .font(.appCallout.monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.appCaption).foregroundStyle(.secondary)
            Text(value)
                .font(.appTitle3.monospacedDigit().weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ProMeSpacing.cardCorner).fill(.background.secondary))
    }
}

private struct LegendList: View {
    struct Slice: Identifiable {
        var id: String { "\(categoryID?.uuidString ?? "none")-\(name)" }
        let categoryID: UUID?
        let name: String
        let minor: Int64
    }
    let slices: [Slice]
    let onTap: (Slice) -> Void

    init(slices: [DashboardModel.CategorySlice], onTap: @escaping (Slice) -> Void) {
        self.slices = slices.map { Slice(categoryID: $0.id, name: $0.name, minor: $0.minor) }
        self.onTap = onTap
    }

    var body: some View {
        let baseCode = AppPreferences.baseCurrency.code
        return VStack(spacing: 6) {
            ForEach(slices.prefix(8)) { slice in
                Button {
                    onTap(slice)
                } label: {
                    HStack {
                        Circle()
                            .fill(legendColor(for: slice.name))
                            .frame(width: 8, height: 8)
                        Text(slice.name)
                            .font(.appCaption)
                            .lineLimit(1)
                        Spacer()
                        Text(Format.amount(slice.minor, code: baseCode))
                            .font(.appCaption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legendColor(for name: String) -> Color {
        Color(hue: Double(abs(name.hashValue % 360)) / 360.0, saturation: 0.55, brightness: 0.85, opacity: 0.9)
    }
}

// MARK: - Model

@MainActor
@Observable
final class DashboardModel {
    struct CurrencyTotal: Equatable, Identifiable {
        var id: String { code }
        let code: String
        let minor: Int64
    }

    struct MonthlyBar: Equatable {
        let label: String
        let income: Int64
        let expense: Int64
    }

    struct CategorySlice: Equatable {
        let id: UUID?
        let name: String
        let minor: Int64
    }

    struct AccountCard: Equatable {
        let accountID: UUID
        let account: MoneyAccountMO
        let balance: Int64
        static func == (lhs: AccountCard, rhs: AccountCard) -> Bool { lhs.accountID == rhs.accountID }
    }

    var netWorth: [CurrencyTotal] = []
    var cash: [CurrencyTotal] = []
    var incomeMonth: [CurrencyTotal] = []
    var expenseMonth: [CurrencyTotal] = []
    var cashFlowMonth: Int64 = 0
    var monthlyBars: [MonthlyBar] = []
    var categorySlices: [CategorySlice] = []
    var accountCards: [AccountCard] = []
    var recent: [TransactionMO] = []
    var upcoming: [RecurringTransactionMO] = []
    var budgetRows: [BudgetService.Row] = []
    var drillDown: DrillDownSelection?
    var baseCode: String = "IRR"

    var isEmpty: Bool {
        accountCards.isEmpty && recent.isEmpty
    }

    func baseText(_ totals: [CurrencyTotal]) -> String {
        let base = totals.first { $0.code == baseCode } ?? totals.first
        guard let base else { return "0" }
        return Format.amount(base.minor, code: base.code)
    }

    func reload(appModel: AppModel) {
        guard let services = appModel.services else { return }
        baseCode = AppPreferences.baseCurrency.code
        let scope = appModel.activeScope
        let preference = AppPreferences.calendar
        let resolver = PeriodResolver(preference: preference)
        let month = resolver.monthContaining(.now)

        do {
            let accounts = try services.accounts.accounts(in: scope)
            let balances = try services.aggregates.accountBalances(accounts)
            accountCards = accounts
                .map { AccountCard(accountID: $0.id, account: $0, balance: balances[$0.id] ?? 0) }

            cash = try services.aggregates.cashTotals(accounts: accounts)
                .map { CurrencyTotal(code: $0.currencyCode, minor: $0.minor) }

            // Net worth = cash + owned assets + receivables − payables − loans.
            var net = cash.first { $0.code == baseCode }?.minor ?? 0
            let assetTotals = try services.assets.totals(scope: scope)
            net += assetTotals.first { $0.currencyCode == baseCode }?.minor ?? 0
            let receivables = try services.debts.all(direction: .receivable, scope: scope)
            net += receivables.filter { $0.status == .open && $0.currencyCode == baseCode }
                .reduce(0) { $0 + $1.remainingMinor }
            let payables = try services.debts.all(direction: .payable, scope: scope)
            net -= payables.filter { $0.status == .open && $0.currencyCode == baseCode }
                .reduce(0) { $0 + $1.remainingMinor }
            let loans = try services.loans.all(scope: scope)
            for loan in loans where loan.currencyCode == baseCode {
                net -= try services.loans.remainingPrincipal(loan)
            }
            netWorth = [CurrencyTotal(code: baseCode, minor: net)]

            let income = try services.aggregates.sum(kind: .income, scope: scope, from: month.start, to: month.end)
            let expense = try services.aggregates.sum(kind: .expense, scope: scope, from: month.start, to: month.end)
            incomeMonth = income.map { CurrencyTotal(code: $0.currencyCode, minor: $0.minor) }
            expenseMonth = expense.map { CurrencyTotal(code: $0.currencyCode, minor: $0.minor) }
            cashFlowMonth = (income.first { $0.currencyCode == baseCode }?.minor ?? 0) - (expense.first { $0.currencyCode == baseCode }?.minor ?? 0)

            // Six-month bars in the base currency.
            let months = resolver.lastMonths(6, endingAt: .now)
            monthlyBars = months.map { range in
                let inc = (try? services.aggregates.sum(kind: .income, scope: scope, from: range.start, to: range.end))?
                    .first { $0.currencyCode == baseCode }?.minor ?? 0
                let exp = (try? services.aggregates.sum(kind: .expense, scope: scope, from: range.start, to: range.end))?
                    .first { $0.currencyCode == baseCode }?.minor ?? 0
                return MonthlyBar(label: resolver.monthLabel(forMonthStart: range.start), income: inc, expense: exp)
            }

            // Category slices for the current month, base currency.
            categorySlices = (try services.aggregates.sumByCategory(kind: .expense, scope: scope, from: month.start, to: month.end))
                .filter { $0.currencyCode == baseCode }
                .prefix(9)
                .map { CategorySlice(id: $0.categoryID, name: $0.categoryName, minor: $0.minor) }

            recent = (try services.transactions.fetch(
                TransactionQuery(scopeID: appModel.scopeSelection == .all ? nil : scope?.id, sort: .date, ascending: false),
                limit: 8
            )) ?? []

            upcoming = (try services.recurring.upcoming(withinDays: 30)) ?? []
            if let scope {
                budgetRows = try services.budgets.rows(
                    monthKey: BudgetService.monthKey(for: .now, preference: preference),
                    scope: scope, from: month.start, to: month.end
                )
            } else {
                budgetRows = []
            }
        } catch {
            // Dashboard failures leave the previous state; never crash.
        }
    }
}

/// Drill-down target: a category slice or an account card.
struct DrillDownSelection: Identifiable {
    var id: String { "\(categoryID?.uuidString ?? "")-\(accountID?.uuidString ?? "")" }
    var categoryName: String?
    var categoryID: UUID?
    var accountID: UUID?
    var accountName: String?

    var title: String {
        categoryName ?? accountName ?? String(localized: "Transactions")
    }
}

/// Filtered transaction list behind chart/account drill-downs.
struct DrillDownView: View {
    @Environment(AppModel.self) private var appModel
    let selection: DrillDownSelection
    @State private var rows: [TransactionMO] = []

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                EmptyStateView(systemImage: "tray", title: selection.title, detail: String(localized: "No transactions in this period."))
            } else {
                List {
                    ForEach(rows, id: \.objectID) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(selection.title)
        .task { load() }
    }

    private func load() {
        guard let services = appModel.services else { return }
        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        let month = resolver.monthContaining(.now)
        let query = TransactionQuery(
            accountID: selection.accountID,
            categoryID: selection.categoryID,
            startDate: month.start,
            endDate: month.end
        )
        rows = (try? services.transactions.fetch(query)) ?? []
    }
}
