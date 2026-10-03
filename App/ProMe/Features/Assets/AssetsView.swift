import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Owned assets (car, home, devices…) with valuations, capitalised
/// purchases and a sale flow that books gain/loss properly.
struct AssetsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [AssetMO] = []
    @State private var showNew = false
    @State private var valuing: AssetMO?
    @State private var selling: AssetMO?
    @State private var editing: AssetMO?
    @State private var confirmDelete: AssetMO?
    @State private var errorMessage: String?
    @State private var totals: [AggregateQueries.CurrencySum] = []

    var body: some View {
        VStack(spacing: 0) {
            if !totals.isEmpty {
                HStack {
                    Text(String(localized: "Total Assets"))
                        .font(.appCallout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(totals.map { Format.amount($0.minor, code: $0.currencyCode) }.joined(separator: " · "))
                        .font(.appCallout.monospacedDigit().weight(.semibold))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "house.and.flag.fill.2.crossed",
                    title: String(localized: "No Assets"),
                    detail: String(localized: "Track what you own — its value flows into your net worth.")
                )
            } else {
                List {
                    ForEach(rows, id: \.objectID) { asset in
                        AssetRowView(asset: asset)
                            .contextMenu {
                                Button(String(localized: "Record Valuation…")) { valuing = asset }
                                if asset.status == .owned {
                                    Button(String(localized: "Sell…")) { selling = asset }
                                }
                                Divider()
                                Button(String(localized: "Delete"), role: .destructive) { confirmDelete = asset }
                            }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Assets"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Asset"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            AssetEditor(asset: nil)
                .frame(minWidth: 440, minHeight: 420)
        }
        .sheet(item: $editing, onDismiss: { reload() }) { asset in
            AssetEditor(asset: asset)
                .frame(minWidth: 440, minHeight: 420)
        }
        .sheet(item: $valuing, onDismiss: { reload() }) { asset in
            AssetValuationSheet(asset: asset)
                .frame(minWidth: 400, minHeight: 250)
        }
        .sheet(item: $selling, onDismiss: { reload() }) { asset in
            AssetSaleSheet(asset: asset)
                .frame(minWidth: 400, minHeight: 300)
        }
        .confirmationDialog(
            String(localized: "Delete this asset?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) { deleteAsset() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Its accounting entries are reversed as well."))
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
        rows = (try? services.assets.all(scope: appModel.activeScope, includeSold: true)) ?? []
        totals = (try? services.assets.totals(scope: appModel.activeScope)) ?? []
    }

    private func deleteAsset() {
        guard let services = appModel.services, let asset = confirmDelete else { return }
        do {
            try services.assets.delete(asset)
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

private struct AssetRowView: View {
    let asset: AssetMO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube")
                .foregroundStyle(asset.status == .owned ? ProMeColor.transfer : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(.appBody.weight(.medium))
                HStack(spacing: 6) {
                    Text(asset.type.displayName)
                    if asset.status == .sold {
                        Text("·")
                        Text(String(localized: "Sold") + " " + (asset.soldAt.map(Format.dateText) ?? ""))
                    } else {
                        Text("·")
                        Text(String(localized: "Valued") + " " + Format.dateText(asset.valuationDate))
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.amount(asset.currentValueMinor, code: asset.currencyCode))
                    .font(.appCallout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(asset.status == .sold ? .secondary : Color.primary)
                Text(String(localized: "bought at \(Format.dateText(asset.purchaseDate)) of \(Format.amount(asset.purchasePriceMinor, code: asset.currencyCode))"))
                    .font(.appCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 230, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

extension AssetType {
    var displayName: String {
        switch self {
        case .vehicle: String(localized: "Vehicle")
        case .property: String(localized: "Property")
        case .electronics: String(localized: "Electronics")
        case .equipment: String(localized: "Equipment")
        case .investment: String(localized: "Investment")
        case .jewelry: String(localized: "Jewelry")
        case .other: String(localized: "Other")
        }
    }
}

/// Create / edit an asset. A funding account capitalises the purchase
/// (Dr Fixed Asset / Cr account); without one the asset is tracked for
/// net worth only.
struct AssetEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let asset: AssetMO?

    @State private var name = ""
    @State private var type: AssetType = .electronics
    @State private var priceText = ""
    @State private var purchaseDate = Date()
    @State private var currencyCode = "IRR"
    @State private var useFunding = false
    @State private var fundingAccount: MoneyAccountMO?
    @State private var notes = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var inlineAccountSheet = false

    private let knownCurrencies = ["IRT", "IRR", "USD", "EUR", "GBP", "AED", "TRY"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(String(localized: "Name"), text: $name)
                Picker(String(localized: "Type"), selection: $type) {
                    ForEach(AssetType.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                if asset == nil {
                    AmountField(title: String(localized: "Purchase Price"), currencyCode: currencyCode, text: $priceText)
                    DatePicker(String(localized: "Purchase Date"), selection: $purchaseDate, displayedComponents: .date)
                    Picker(String(localized: "Currency"), selection: $currencyCode) {
                        ForEach(knownCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    Toggle(String(localized: "Paid From Account"), isOn: $useFunding)
                    if useFunding {
                        AccountPicker(title: String(localized: "Account"), selection: $fundingAccount, accounts: accounts, onNewAccount: { inlineAccountSheet = true })
                    }
                } else {
                    LabeledContent(String(localized: "Purchase Price"), value: Format.amount(asset?.purchasePriceMinor ?? 0, code: asset?.currencyCode ?? "IRR"))
                }
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .onAppear(perform: load)
        .sheet(isPresented: $inlineAccountSheet) {
            AccountEditor(account: nil, onCreated: { created in
                if !accounts.contains(where: { $0.objectID == created.objectID }) {
                    accounts.append(created)
                }
                fundingAccount = created
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
        accounts = (try? services.accounts.allAccounts()) ?? []
        fundingAccount = accounts.first
        if let asset {
            name = asset.name
            type = asset.type
            currencyCode = asset.currencyCode
            notes = asset.notes ?? ""
        }
    }

    private func save() {
        guard let services = appModel.services else { return }
        let currency = Currency.resolving(currencyCode)
        if let asset {
            do {
                try contextUpdate(asset, services: services)
                dismiss()
            } catch {
                errorMessage = ProMeLog.record(error)
            }
            return
        }
        let price = MoneyInput.parseMinorUnits(priceText, currency: currency) ?? 0
        guard let scope = appModel.activeScope ?? appModel.personalScope else {
            errorMessage = String(localized: "No scope available.")
            return
        }
        do {
            _ = try services.assets.create(
                AssetService.NewAsset(
                    name: name,
                    type: type,
                    purchasePriceMinor: price,
                    purchaseDate: purchaseDate,
                    currency: currency,
                    fundingAccount: useFunding ? fundingAccount : nil,
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

    private func contextUpdate(_ asset: AssetMO, services: AppModel.Services) throws {
        try services.assets.rename(asset, name: name)
        asset.type = type
        asset.notes = notes.isEmpty ? nil : notes
        try appModel.persistence?.saveViewContext()
    }
}

private struct AssetValuationSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let asset: AssetMO

    @State private var valueText = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(String(localized: "Asset"), value: asset.name)
                LabeledContent(String(localized: "Current Value"), value: Format.amount(asset.currentValueMinor, code: asset.currencyCode))
                AmountField(title: String(localized: "New Value"), currencyCode: asset.currencyCode, text: $valueText)
                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            var decimal = Decimal(asset.currentValueMinor)
            for _ in 0..<Currency.resolving(asset.currencyCode).minorUnitScale { decimal /= 10 }
            valueText = "\(decimal)"
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
        guard let minor = MoneyInput.parseMinorUnits(valueText, currency: Currency.resolving(asset.currencyCode)) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        do {
            try services.assets.recordValuation(asset, valueMinor: minor, date: date)
            appModel.bumpData()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}

private struct AssetSaleSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let asset: AssetMO

    @State private var proceedsText = ""
    @State private var date = Date()
    @State private var account: MoneyAccountMO?
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(String(localized: "Asset"), value: asset.name)
                LabeledContent(String(localized: "Book Value"), value: Format.amount(asset.currentValueMinor, code: asset.currencyCode))
                AmountField(title: String(localized: "Sale Proceeds"), currencyCode: asset.currencyCode, text: $proceedsText)
                AccountPicker(title: String(localized: "Account"), selection: $account, accounts: accounts)
                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Sell"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onAppear(perform: load)
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
        accounts = (try? services.accounts.accounts(in: asset.scope)) ?? []
        account = accounts.first
        var decimal = Decimal(asset.currentValueMinor)
        for _ in 0..<Currency.resolving(asset.currencyCode).minorUnitScale { decimal /= 10 }
        proceedsText = "\(decimal)"
    }

    private func save() {
        guard let services = appModel.services, let account else { return }
        guard let minor = MoneyInput.parseMinorUnits(proceedsText, currency: Currency.resolving(asset.currencyCode)) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        do {
            try services.assets.sell(asset, account: account, proceedsMinor: minor, date: date)
            appModel.bumpData()
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
