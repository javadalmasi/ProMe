import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Insurance policies; premiums post through the recurring engine with the
/// seeded insurance expense category.
struct InsuranceView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [InsuranceMO] = []
    @State private var showNew = false
    @State private var confirmDelete: InsuranceMO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "shield.lefthalf.filled",
                    title: String(localized: "No Insurances"),
                    detail: String(localized: "Register policies and let premiums recur automatically.")
                )
            } else {
                List {
                    ForEach(rows, id: \.objectID) { insurance in
                        InsuranceRowView(insurance: insurance)
                            .contextMenu {
                                if insurance.isActive {
                                    Button(String(localized: "Cancel Policy"), role: .destructive) { cancel(insurance) }
                                }
                                Divider()
                                Button(String(localized: "Delete"), role: .destructive) { confirmDelete = insurance }
                            }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Insurance"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Insurance"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            InsuranceEditor()
                .frame(minWidth: 440, minHeight: 460)
        }
        .confirmationDialog(
            String(localized: "Delete this insurance?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) { deleteInsurance() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "The premium recurrence is stopped as well."))
        }
        .alert(String(localized: "Something went wrong"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        rows = (try? services.insurances.all(scope: appModel.activeScope)) ?? []
    }

    private func cancel(_ insurance: InsuranceMO) {
        do {
            try appModel.services?.insurances.cancel(insurance)
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }

    private func deleteInsurance() {
        guard let services = appModel.services, let insurance = confirmDelete else { return }
        do {
            try services.insurances.delete(insurance)
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

private struct InsuranceRowView: View {
    let insurance: InsuranceMO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(insurance.isActive ? ProMeColor.transfer : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(insurance.organization).font(.appBody.weight(.medium))
                HStack(spacing: 6) {
                    Text(insurance.type.displayName)
                    if let next = insurance.recurring?.nextDueAt, insurance.isActive {
                        Text("·")
                        Text(String(localized: "Next") + " " + Format.dateText(next))
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.amount(insurance.premiumMinor, code: insurance.currencyCode))
                    .font(.appCallout.monospacedDigit().weight(.semibold))
                Text(insurance.period.displayName)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

extension InsuranceType {
    var displayName: String {
        switch self {
        case .socialSecurity: String(localized: "Social Security")
        case .supplementary: String(localized: "Supplementary")
        case .car: String(localized: "Car Insurance")
        case .life: String(localized: "Life Insurance")
        case .health: String(localized: "Health Insurance")
        case .other: String(localized: "Other")
        }
    }
}

extension PaymentPeriod {
    var displayName: String {
        switch self {
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Quarterly")
        case .yearly: String(localized: "Yearly")
        }
    }
}

struct InsuranceEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var type: InsuranceType = .supplementary
    @State private var organization = ""
    @State private var policyNumber = ""
    @State private var contractNumber = ""
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date().addingTimeInterval(365 * 86400)
    @State private var amountText = ""
    @State private var period: PaymentPeriod = .monthly
    @State private var account: MoneyAccountMO?
    @State private var createRecurring = true
    @State private var notes = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var inlineAccountSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(String(localized: "Type"), selection: $type) {
                    ForEach(InsuranceType.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                TextField(String(localized: "Organization"), text: $organization)
                TextField(String(localized: "Policy Number"), text: $policyNumber)
                TextField(String(localized: "Contract Number"), text: $contractNumber)
                AmountField(title: String(localized: "Premium"), currencyCode: account?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)
                Picker(String(localized: "Period"), selection: $period) {
                    ForEach(PaymentPeriod.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                DatePicker(String(localized: "Start Date"), selection: $startDate, displayedComponents: .date)
                Toggle(String(localized: "Has End Date"), isOn: $hasEnd)
                if hasEnd {
                    DatePicker(String(localized: "End Date"), selection: $endDate, displayedComponents: .date)
                }
                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts, onNewAccount: { inlineAccountSheet = true })
                Toggle(String(localized: "Post Automatically"), isOn: $createRecurring)
                TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                    .lineLimit(2...3)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(organization.trimmingCharacters(in: .whitespaces).isEmpty || account == nil)
            }
            .padding()
        }
        .onAppear(perform: load)
        .sheet(isPresented: $inlineAccountSheet) {
            AccountEditor(account: nil, onCreated: { created in
                if !accounts.contains(where: { $0.objectID == created.objectID }) {
                    accounts.append(created)
                }
                account = created
            })
            .frame(minWidth: 440, minHeight: 430)
        }
        .alert(String(localized: "Cannot Save"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() {
        guard !loaded, let services = appModel.services else { return }
        loaded = true
        accounts = (try? services.accounts.accounts(in: appModel.activeScope)) ?? []
        if accounts.isEmpty {
            accounts = (try? services.accounts.allAccounts()) ?? []
        }
        account = accounts.first
    }

    private func save() {
        guard let services = appModel.services, let account else { return }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: account.currency) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        guard let scope = appModel.activeScope ?? appModel.personalScope else {
            errorMessage = String(localized: "No scope available.")
            return
        }
        do {
            _ = try services.insurances.create(
                InsuranceService.NewInsurance(
                    type: type,
                    organization: organization,
                    policyNumber: policyNumber.isEmpty ? nil : policyNumber,
                    contractNumber: contractNumber.isEmpty ? nil : contractNumber,
                    startDate: startDate,
                    endDate: hasEnd ? endDate : nil,
                    premiumMinor: minor,
                    period: period,
                    account: account,
                    createRecurring: createRecurring,
                    notes: notes.isEmpty ? nil : notes
                ),
                in: scope
            )
            appModel.bumpData()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
