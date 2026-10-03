import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// A wrapper so the CSV text can be handed to the cross-platform
/// `.fileExporter` modifier (works on macOS, iOS and iPadOS alike).
struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Report Center: cash flow, income & expense, net worth — with CSV export.
struct ReportsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var report: ReportKind = .cashFlow
    @State private var period: PeriodOption = .thisMonth
    @State private var model = ReportsModel()
    @State private var exportDone: String?
    @State private var exportItem: CSVExportDocument?
    @State private var exportPresented = false

    enum ReportKind: String, CaseIterable {
        case cashFlow
        case incomeExpense
        case netWorth

        var title: String {
            switch self {
            case .cashFlow: String(localized: "Cash Flow")
            case .incomeExpense: String(localized: "Income & Expense")
            case .netWorth: String(localized: "Net Worth")
            }
        }
    }

    enum PeriodOption: String, CaseIterable {
        case thisMonth, lastMonth, thisYear, all
        var title: String {
            switch self {
            case .thisMonth: String(localized: "This Month")
            case .lastMonth: String(localized: "Last Month")
            case .thisYear: String(localized: "This Year")
            case .all: String(localized: "All Time")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker(String(localized: "Report"), selection: $report) {
                    ForEach(ReportKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)

                Picker(String(localized: "Period"), selection: $period) {
                    ForEach(PeriodOption.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .frame(width: 160)

                Spacer()

                Button {
                    exportCSV()
                } label: {
                    Label(String(localized: "Export CSV"), systemImage: "square.and.arrow.up")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Group {
                switch report {
                case .cashFlow: cashFlow
                case .incomeExpense: incomeExpense
                case .netWorth: netWorth
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(String(localized: "Reports"))
        .task(id: "\(report.rawValue)|\(period.rawValue)|\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .fileExporter(
            isPresented: $exportPresented,
            document: exportItem,
            contentType: .commaSeparatedText,
            defaultFilename: "ProMe-Transactions.csv"
        ) { result in
            exportDone = switch result {
            case .success: String(localized: "Exported successfully.")
            case .failure(let error): error.localizedDescription
            }
        }
        .overlay(alignment: .bottom) {
            if let message = exportDone {
                Text(message)
                    .font(.appCallout)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                    .padding(.bottom, 12)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        self.exportDone = nil
                    }
            }
        }
    }

    private var cashFlow: some View {
        ScrollView {
            Card {
                VStack(spacing: 10) {
                    flowRow(String(localized: "Beginning Balance"), model.beginning, .primary)
                    Divider()
                    flowRow(String(localized: "Income"), model.income, ProMeColor.income)
                    flowRow(String(localized: "Expense"), model.expense, ProMeColor.expense)
                    flowRow(String(localized: "Net Flow"), model.netFlow, model.netFlow >= 0 ? ProMeColor.income : ProMeColor.expense)
                    Divider()
                    flowRow(String(localized: "Ending Balance"), model.ending, .primary)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var incomeExpense: some View {
        HStack(alignment: .top, spacing: 16) {
            categoryTable(title: String(localized: "Income by Category"), sums: model.incomeByCategory, color: ProMeColor.income)
            categoryTable(title: String(localized: "Expense by Category"), sums: model.expenseByCategory, color: ProMeColor.expense)
        }
        .padding(.horizontal, 20)
    }

    private var netWorth: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    VStack(spacing: 8) {
                        flowRow(String(localized: "Cash"), model.ending, .primary)
                        flowRow(String(localized: "Assets"), model.assetsTotalMinor, .primary)
                        ForEach(Array(model.obligations.enumerated()), id: \.offset) { _, row in
                            flowRow(row.name, row.minor, row.minor >= 0 ? ProMeColor.income : ProMeColor.expense)
                        }
                        Divider()
                        flowRow(String(localized: "Net Worth"), model.netWorthTotal, model.netWorthTotal >= 0 ? .primary : ProMeColor.expense)
                    }
                }
                if !model.assetRows.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Assets")).font(.appHeadline)
                            ForEach(model.assetRows, id: \.objectID) { asset in
                                HStack {
                                    Image(systemName: "cube").foregroundStyle(ProMeColor.transfer).font(.appCaption)
                                    Text(asset.name).font(.appCallout)
                                    Spacer()
                                    Text(Format.amount(asset.currentValueMinor, code: asset.currencyCode))
                                        .font(.appCallout.monospacedDigit())
                                }
                            }
                        }
                    }
                }
                ForEach(model.netWorthGroups, id: \.currency) { group in
                    Card {
                        VStack(spacing: 8) {
                            HStack {
                                Text(group.currency).font(.appHeadline)
                                Spacer()
                                Text(Format.amount(group.net, code: group.currency))
                                    .font(.appHeadline.monospacedDigit())
                                    .foregroundStyle(group.net >= 0 ? Color.primary : ProMeColor.expense)
                            }
                            ForEach(group.rows, id: \.account.objectID) { row in
                                HStack {
                                    Image(systemName: row.account.type.systemImage)
                                        .foregroundStyle(ProMeColor.transfer)
                                        .font(.appCaption)
                                    Text(row.account.name).font(.appCallout)
                                    Spacer()
                                    Text(Format.amount(row.balance, code: group.currency))
                                        .font(.appCallout.monospacedDigit())
                                        .foregroundStyle(row.balance < 0 ? ProMeColor.expense : Color.primary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryTable(title: String, sums: [AggregateQueries.CategorySum], color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.appHeadline)
                if sums.isEmpty {
                    Text(String(localized: "No data in this period."))
                        .font(.appCallout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(sums.enumerated()), id: \.offset) { _, sum in
                    HStack {
                        Text(sum.categoryName).font(.appCallout)
                        Spacer()
                        Text(Format.amount(sum.minor, code: sum.currencyCode))
                            .font(.appCallout.monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flowRow(_ title: String, _ minor: Int64, _ color: Color) -> some View {
        HStack {
            Text(title).font(.appCallout)
            Spacer()
            Text(Format.amount(minor, code: model.baseCode))
                .font(.appCallout.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Data

    private func reload() {
        guard let services = appModel.services else { return }
        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        let now = Date()
        var start: Date = .distantPast
        var end: Date = .distantFuture
        switch period {
        case .thisMonth:
            let month = resolver.monthContaining(now)
            start = month.start
            end = month.end
        case .lastMonth:
            let month = resolver.monthContaining(now)
            if let previous = resolver.calendar.date(byAdding: .month, value: -1, to: month.start) {
                let previousMonth = resolver.monthContaining(previous)
                start = previousMonth.start
                end = previousMonth.end
            }
        case .thisYear:
            if let year = resolver.calendar.dateInterval(of: .year, for: now) {
                start = year.start
                end = year.end
            }
        case .all:
            break
        }
        model.reload(appModel: appModel, from: start, to: end, preference: AppPreferences.calendar)
    }

    private func exportCSV() {
        guard let services = appModel.services else { return }
        let rows: [TransactionMO] = (try? services.transactions.fetch(TransactionQuery(sort: .date, ascending: true))) ?? []
        exportItem = CSVExportDocument(text: Self.buildCSV(rows: rows))
        exportPresented = true
    }

    static func buildCSV(rows: [TransactionMO]) -> String {
        func escape(_ value: String) -> String {
            value.contains(",") || value.contains("\"") || value.contains("\n")
                ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                : value
        }
        var lines = ["date,kind,amount,currency,account,from,to,category,counterparty,memo,reference"]
        let iso = ISO8601DateFormatter()
        for transaction in rows {
            var fields: [String] = []
            fields.append(iso.string(from: transaction.postedAt))
            fields.append(transaction.kind.rawValue)
            fields.append(String(transaction.amountMinor))
            fields.append(transaction.currencyCode)
            fields.append(transaction.account?.name ?? "")
            fields.append(transaction.fromAccount?.name ?? "")
            fields.append(transaction.toAccount?.name ?? "")
            fields.append(transaction.category?.name ?? "")
            fields.append(transaction.counterparty?.displayName ?? "")
            fields.append(transaction.memo ?? "")
            fields.append(transaction.referenceNo ?? "")
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class ReportsModel {
    struct NetWorthRow {
        let account: MoneyAccountMO
        let balance: Int64
    }
    struct NetWorthGroup: Identifiable {
        var id: String { currency }
        let currency: String
        let rows: [NetWorthRow]
        var assets: Int64 { rows.filter { $0.balance >= 0 }.reduce(0) { $0 + $1.balance } }
        var liabilities: Int64 { rows.filter { $0.balance < 0 }.reduce(0) { $0 + $1.balance } }
        var net: Int64 { assets + liabilities }
    }

    var baseCode = "IRR"
    var beginning: Int64 = 0
    var income: Int64 = 0
    var expense: Int64 = 0
    var ending: Int64 = 0
    var netFlow: Int64 { income - expense }
    var incomeByCategory: [AggregateQueries.CategorySum] = []
    var expenseByCategory: [AggregateQueries.CategorySum] = []
    var netWorthGroups: [NetWorthGroup] = []
    var assetRows: [AssetMO] = []
    var obligations: [(name: String, minor: Int64)] = []
    var assetsTotalMinor: Int64 = 0
    var netWorthTotal: Int64 = 0

    func reload(appModel: AppModel, from: Date?, to: Date?, preference: CalendarPreference) {
        guard let services = appModel.services else { return }
        baseCode = AppPreferences.baseCurrency.code
        let scope = appModel.activeScope
        let start = from ?? Date.distantPast
        let end = to ?? Date.distantFuture

        let incomeSums = (try? services.aggregates.sum(kind: .income, scope: scope, from: start, to: end)) ?? []
        let expenseSums = (try? services.aggregates.sum(kind: .expense, scope: scope, from: start, to: end)) ?? []
        income = incomeSums.first { $0.currencyCode == baseCode }?.minor ?? 0
        expense = expenseSums.first { $0.currencyCode == baseCode }?.minor ?? 0

        let accounts = (try? services.accounts.accounts(in: scope)) ?? []
        let balances = (try? services.aggregates.accountBalances(accounts)) ?? [:]
        let totals = (try? services.aggregates.cashTotals(accounts: accounts)) ?? []
        ending = totals.first { $0.currencyCode == baseCode }?.minor ?? 0
        beginning = ending - netFlow

        incomeByCategory = ((try? services.aggregates.sumByCategory(kind: .income, scope: scope, from: start, to: end)) ?? [])
            .filter { $0.currencyCode == baseCode }
        expenseByCategory = ((try? services.aggregates.sumByCategory(kind: .expense, scope: scope, from: start, to: end)) ?? [])
            .filter { $0.currencyCode == baseCode }

        var byCurrency: [String: [NetWorthRow]] = [:]
        for account in accounts {
            byCurrency[account.currencyCode, default: []].append(NetWorthRow(account: account, balance: balances[account.id] ?? 0))
        }
        netWorthGroups = byCurrency
            .map { NetWorthGroup(currency: $0.key, rows: $0.value.sorted { $0.balance > $1.balance }) }
            .sorted { $0.currency < $1.currency }

        // Assets and obligations complete the net worth picture.
        let assetRowsFetched = (try? services.assets.all(scope: scope, includeSold: false)) ?? []
        assetRows = assetRowsFetched
        let assetsTotal = (try? services.assets.totals(scope: scope))?
            .first { $0.currencyCode == baseCode }?.minor ?? 0
        assetsTotalMinor = assetsTotal

        var obligationsList: [(name: String, minor: Int64)] = []
        let receivableRows = (try? services.debts.all(direction: .receivable, scope: scope)) ?? []
        for debt in receivableRows where debt.status == .open && debt.currencyCode == baseCode {
            obligationsList.append((debt.counterparty?.displayName ?? "—", Int64(debt.remainingMinor)))
        }
        let payableRows = (try? services.debts.all(direction: .payable, scope: scope)) ?? []
        for debt in payableRows where debt.status == .open && debt.currencyCode == baseCode {
            obligationsList.append((debt.counterparty?.displayName ?? "—", -Int64(debt.remainingMinor)))
        }
        let loanRows = (try? services.loans.all(scope: scope)) ?? []
        for loan in loanRows where loan.currencyCode == baseCode {
            let remaining = (try? services.loans.remainingPrincipal(loan)) ?? 0
            obligationsList.append((loan.lenderName, -remaining))
        }
        obligations = obligationsList
        let cashBase = ending
        netWorthTotal = cashBase + assetsTotal + obligationsList.reduce(0) { $0 + $1.minor }
    }
}
