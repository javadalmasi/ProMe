import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Professional transaction list with search, filters, sorting, an
/// inspector for details, context menus and undo for deletions.
struct TransactionsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [TransactionMO] = []
    @State private var searchText = ""
    @State private var kinds: Set<TransactionKind> = []
    @State private var period: PeriodOption = .all
    @FocusState private var searchFocused: Bool
    @State private var selected: TransactionMO?
    @State private var editing: TransactionMO?
    @State private var duplicating: TransactionMO?
    @State private var showImport = false
    @State private var confirmDelete: TransactionMO?
    @State private var pendingUndo: AppModel.UndoSnapshot?
    @State private var errorMessage: String?

    enum PeriodOption: String, CaseIterable {
        case thisMonth
        case lastMonth
        case last3Months
        case thisYear
        case all

        var title: String {
            switch self {
            case .thisMonth: String(localized: "This Month")
            case .lastMonth: String(localized: "Last Month")
            case .last3Months: String(localized: "Last 3 Months")
            case .thisYear: String(localized: "This Year")
            case .all: String(localized: "All Time")
            }
        }

        func range(now: Date = .now, preference: CalendarPreference) -> (start: Date, end: Date)? {
            let resolver = PeriodResolver(preference: preference)
            let month = resolver.monthContaining(now)
            switch self {
            case .thisMonth: return month
            case .lastMonth:
                guard let previous = resolver.calendar.date(byAdding: .month, value: -1, to: month.start) else { return nil }
                return resolver.monthContaining(previous)
            case .last3Months:
                guard let start = resolver.calendar.date(byAdding: .month, value: -2, to: month.start) else { return nil }
                return (resolver.calendar.startOfDay(for: start), month.end)
            case .thisYear:
                guard let interval = resolver.calendar.dateInterval(of: .year, for: now) else { return nil }
                return (interval.start, interval.end)
            case .all: return nil
            }
        }
    }

    /// Re-fetch trigger: any filter change (or data change elsewhere).
    private var fetchKey: String {
        let kindKey = kinds.map(\.rawValue).sorted().joined(separator: ",")
        return "\(searchText)|\(kindKey)|\(period.rawValue)|\(appModel.scopeSelection)|\(appModel.dataEpoch)|\(undoTick)"
    }
    @State private var undoTick = 0

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "tray.full",
                    title: String(localized: "No Transactions"),
                    detail: String(localized: "Press ⌘N to record your first transaction.")
                )
            } else {
                list
            }
        }
        .navigationTitle(String(localized: "Transactions"))
        .searchable(text: $searchText, prompt: Text(String(localized: "Search description, category, account…")))
        .searchFocusedIfAvailable($searchFocused)
        .onChange(of: appModel.focusSearchToken) {
            searchFocused = true
        }
        .toolbar { filterToolbar }
        .task(id: fetchKey) { reload() }
        .inspector(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let selected {
                TransactionDetailView(transaction: selected) {
                    editing = selected
                } onDuplicate: {
                    duplicating = selected
                } onDelete: {
                    confirmDelete = selected
                }
            }
        }
        .sheet(item: $editing, onDismiss: { reload() }) { transaction in
            TransactionEditor(mode: .edit(transaction))
                .frame(minWidth: 460, minHeight: 460)
        }
        .sheet(item: $duplicating, onDismiss: { reload() }) { transaction in
            TransactionEditor(mode: .duplicate(transaction))
                .frame(minWidth: 460, minHeight: 460)
        }
        .sheet(isPresented: $showImport, onDismiss: { reload() }) {
            ImportWizardView()
                .frame(minWidth: 640, minHeight: 520)
        }
        .confirmationDialog(
            String(localized: "Delete this transaction?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                deleteSelected()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Its accounting entry is removed as well. You can undo right after."))
        }
        .alert(String(localized: "Something went wrong"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var list: some View {
        List(selection: $selected) {
            ForEach(rows, id: \.objectID) { transaction in
                TransactionRowView(transaction: transaction)
                    .tag(transaction)
                    .contextMenu {
                        Button(String(localized: "Edit")) { editing = transaction }
                        Button(String(localized: "Duplicate")) { duplicating = transaction }
                        if transaction.isReconciled {
                            Button(String(localized: "Mark Unreconciled")) { toggleReconciled(transaction) }
                        } else {
                            Button(String(localized: "Mark Reconciled")) { toggleReconciled(transaction) }
                        }
                        Divider()
                        Button(String(localized: "Delete"), role: .destructive) { confirmDelete = transaction }
                    }
            }
        }
        .appListStyle()
    }

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker(String(localized: "Period"), selection: $period) {
                    ForEach(PeriodOption.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                Divider()
                ForEach([TransactionKind.income, .expense, .transfer, .ownerContribution, .ownerWithdrawal], id: \.self) { kind in
                    Toggle(kind.displayName, isOn: Binding(
                        get: { kinds.contains(kind) },
                        set: { included in
                            if included { kinds.insert(kind) } else { kinds.remove(kind) }
                        }
                    ))
                }
                if !kinds.isEmpty || period != .all {
                    Divider()
                    Button(String(localized: "Clear Filters")) {
                        kinds = []
                        period = .all
                    }
                }
            } label: {
                Label(String(localized: "Filter"), systemImage: kinds.isEmpty && period == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }

            Menu {
                Button {
                    showImport = true
                } label: {
                    Label(String(localized: "Import CSV…"), systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help(Text(String(localized: "Import CSV…")))

            if let pendingUndo, undoTick > 0 {
                Button {
                    if appModel.undoDelete(pendingUndo) {
                        self.pendingUndo = nil
                        undoTick += 1
                        reload()
                    }
                } label: {
                    Label(String(localized: "Undo"), systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        var query = TransactionQuery(
            text: searchText,
            scopeID: appModel.scopeSelection == .all ? nil : appModel.activeScope?.id,
            kinds: kinds,
            sort: .date,
            ascending: false
        )
        if let range = period.range(preference: AppPreferences.calendar) {
            query.startDate = range.start
            query.endDate = range.end
        }
        rows = (try? services.transactions.fetch(query)) ?? []
    }

    private func deleteSelected() {
        guard let services = appModel.services, let transaction = confirmDelete else { return }
        pendingUndo = appModel.makeSnapshot(of: transaction)
        do {
            try services.posting.delete(transaction)
            selected = nil
            undoTick += 1
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }

    private func toggleReconciled(_ transaction: TransactionMO) {
        transaction.isReconciled.toggle()
        try? appModel.persistence?.saveViewContext()
        reload()
    }
}

/// One table-like row: date, kind badge, description, category, account,
/// signed amount. Color is never the only signal — amounts carry signs.
struct TransactionRowView: View {
    let transaction: TransactionMO

    var body: some View {
        HStack(spacing: 12) {
            Text(Format.dateText(transaction.postedAt))
                .font(.appCallout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Image(systemName: transaction.kind.systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.memo?.isEmpty == false ? transaction.memo! : transaction.kind.displayName)
                    .font(.appBody.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let category = transaction.category {
                        Text(category.name)
                    }
                    if let account = displayAccount {
                        Text("·").foregroundStyle(.tertiary)
                        Text(account.name)
                    }
                    if transaction.isReconciled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.appCaption2)
                            .foregroundStyle(.green)
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(signedAmount)
                .font(.appCallout.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var displayAccount: MoneyAccountMO? {
        transaction.account ?? transaction.fromAccount ?? transaction.toAccount
    }

    private var tint: Color {
        switch transaction.kind {
        case .income: ProMeColor.income
        case .expense: ProMeColor.expense
        case .transfer, .ownerContribution, .ownerWithdrawal: ProMeColor.transfer
        case .refund: .orange
        default: .secondary
        }
    }

    private var signedAmount: String {
        let base = Format.amount(transaction.amountMinor, code: transaction.currencyCode)
        switch transaction.kind {
        case .income, .refund: return "+" + base
        case .expense: return "−" + base
        case .transfer, .ownerContribution, .ownerWithdrawal: return base
        default: return base
        }
    }
}

/// Inspector with every field plus edit/duplicate/delete actions.
struct TransactionDetailView: View {
    let transaction: TransactionMO
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(transaction.kind.displayName, systemImage: transaction.kind.systemImage)
                    .font(.appTitle3.weight(.semibold))

                if let memo = transaction.memo, !memo.isEmpty {
                    Text(memo).font(.appTitle2.weight(.medium))
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        row(String(localized: "Amount"), Format.amount(transaction.amountMinor, code: transaction.currencyCode))
                        row(String(localized: "Date"), Format.dateText(transaction.postedAt))
                        if let account = transaction.account {
                            row(String(localized: "Account"), account.name)
                        }
                        if let from = transaction.fromAccount, let to = transaction.toAccount {
                            row(String(localized: "From"), from.name)
                            row(String(localized: "To"), to.name)
                        }
                        if let category = transaction.category {
                            row(String(localized: "Category"), category.name)
                        }
                        if let scope = transaction.scope {
                            row(String(localized: "Scope"), scope.name)
                        }
                        if let counterparty = transaction.counterparty {
                            row(String(localized: "Counterparty"), counterparty.displayName)
                        }
                        if let reference = transaction.referenceNo, !reference.isEmpty {
                            row(String(localized: "Reference"), reference)
                        }
                        if let notes = transaction.notes, !notes.isEmpty {
                            row(String(localized: "Notes"), notes)
                        }
                        row(String(localized: "Reconciled"), transaction.isReconciled ? "✓" : "—")
                    }
                }

                HStack {
                    Button(String(localized: "Edit"), action: onEdit)
                    .keyboardShortcut("e", modifiers: .command)
                    Button(String(localized: "Duplicate"), action: onDuplicate)
                    Spacer()
                    Button(String(localized: "Delete"), role: .destructive, action: onDelete)
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
            .padding(20)
        }
        .inspectorColumnWidth(min: 260, ideal: 320)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.appCallout)
    }
}

/// `searchFocused` is macOS 15+ / iOS 18+; on older systems ⌘F still opens
/// the transactions screen, it just does not focus the field.
extension View {
    @ViewBuilder
    func searchFocusedIfAvailable(_ value: FocusState<Bool>.Binding) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            self.searchFocused(value)
        } else {
            self
        }
    }
}
