import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Businesses overview: per-scope summary cards plus creation/deletion.
struct BusinessesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var showNew = false
    @State private var summaries: [ScopeSummary] = []
    @State private var confirmDelete: FinancialScopeMO?
    @State private var errorMessage: String?

    struct ScopeSummary: Identifiable {
        let id: UUID
        let scope: FinancialScopeMO
        let accountCount: Int
        let incomeMinor: Int64
        let expenseMinor: Int64
        let currencyCode: String
        var profitMinor: Int64 { incomeMinor - expenseMinor }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                ForEach(summaries) { summary in
                    summaryCard(summary)
                }
            }
            .padding(20)
        }
        .navigationTitle(String(localized: "Businesses"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Business"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            BusinessEditor()
                .frame(minWidth: 400, minHeight: 280)
        }
        .confirmationDialog(
            String(localized: "Delete this business?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                deleteBusiness()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Only empty businesses can be deleted."))
        }
        .alert(String(localized: "Something went wrong"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func summaryCard(_ summary: ScopeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: summary.scope.kind == .personal ? "person.crop.circle" : "briefcase")
                    .foregroundStyle(ProMeColor.transfer)
                Text(summary.scope.name).font(.appHeadline)
                Spacer()
                if summary.scope.kind == .business {
                    Menu {
                        Button(String(localized: "Open in Transactions")) {
                            appModel.scopeSelection = .scope(summary.id)
                            appModel.selectedRoute = .transactions
                        }
                        Divider()
                        Button(String(localized: "Delete"), role: .destructive) { confirmDelete = summary.scope }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            Text(String(localized: "\(summary.accountCount) accounts"))
                .font(.appCaption)
                .foregroundStyle(.secondary)

            Divider()
            row(String(localized: "Income"), Format.amount(summary.incomeMinor, code: summary.currencyCode), ProMeColor.income)
            row(String(localized: "Expense"), Format.amount(summary.expenseMinor, code: summary.currencyCode), ProMeColor.expense)
            row(String(localized: "Profit"), Format.amount(summary.profitMinor, code: summary.currencyCode), summary.profitMinor >= 0 ? ProMeColor.income : ProMeColor.expense)
        }
        .padding(ProMeSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ProMeSpacing.cardCorner).fill(.background.secondary))
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title).font(.appCallout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.appCallout.monospacedDigit().weight(.semibold)).foregroundStyle(color)
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        appModel.reloadScopes()
        let resolver = PeriodResolver(preference: AppPreferences.calendar)
        let month = resolver.monthContaining(.now)
        let base = AppPreferences.baseCurrency.code

        summaries = appModel.scopesList.map { scope in
            let income = (try? services.aggregates.sum(kind: .income, scope: scope, from: month.start, to: month.end)) ?? []
            let expense = (try? services.aggregates.sum(kind: .expense, scope: scope, from: month.start, to: month.end)) ?? []
            let incomeMinor = income.first { $0.currencyCode == base }?.minor ?? 0
            let expenseMinor = expense.first { $0.currencyCode == base }?.minor ?? 0
            return ScopeSummary(
                id: scope.id,
                scope: scope,
                accountCount: scope.accounts.count,
                incomeMinor: incomeMinor,
                expenseMinor: expenseMinor,
                currencyCode: base
            )
        }
    }

    private func deleteBusiness() {
        guard let services = appModel.services, let scope = confirmDelete else { return }
        do {
            try services.scopes.delete(scope)
            appModel.reloadScopes()
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

struct BusinessEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var tradeName = ""
    @State private var startDate = Date()
    @State private var currencyCode = AppPreferences.baseCurrency.code
    @State private var errorMessage: String?

    private let knownCurrencies = ["IRT", "IRR", "USD", "EUR", "GBP", "AED", "TRY"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(String(localized: "Business Name"), text: $name)
                TextField(String(localized: "Trade Name"), text: $tradeName)
                DatePicker(String(localized: "Start Date"), selection: $startDate, displayedComponents: .date)
                Picker(String(localized: "Main Currency"), selection: $currencyCode) {
                    ForEach(knownCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .alert(String(localized: "Cannot Save"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard let services = appModel.services else { return }
        do {
            _ = try services.scopes.createBusiness(
                name: name,
                tradeName: tradeName.isEmpty ? nil : tradeName,
                startDate: startDate,
                baseCurrency: .resolving(currencyCode)
            )
            appModel.reloadScopes()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
