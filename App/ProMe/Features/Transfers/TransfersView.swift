import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Transfers between accounts, including owner contribution / withdrawal
/// when the two accounts live in different scopes. Transfers are plain
/// money movement — never income, never expense.
struct TransfersView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rows: [TransactionMO] = []
    @State private var showNew = false
    @State private var confirmDelete: TransactionMO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.left.arrow.right",
                    title: String(localized: "No Transfers"),
                    detail: String(localized: "Move money between your accounts; balances update automatically.")
                )
            } else {
                List {
                    ForEach(rows, id: \.objectID) { transaction in
                        TransferRowView(transaction: transaction)
                            .contextMenu {
                                Button(String(localized: "Delete"), role: .destructive) { confirmDelete = transaction }
                            }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Transfers"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Transfer"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(appModel.scopeSelection)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            TransferEditor()
                .frame(minWidth: 420, minHeight: 330)
        }
        .confirmationDialog(
            String(localized: "Delete this transfer?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let transfer = confirmDelete {
                    try? appModel.services?.posting.delete(transfer)
                    reload()
                }
                confirmDelete = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
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
        let query = TransactionQuery(
            scopeID: appModel.scopeSelection == .all ? nil : appModel.activeScope?.id,
            kinds: [.transfer, .ownerContribution, .ownerWithdrawal],
            sort: .date,
            ascending: false
        )
        rows = (try? services.transactions.fetch(query)) ?? []
    }
}

private struct TransferRowView: View {
    let transaction: TransactionMO

    var body: some View {
        HStack(spacing: 12) {
            Text(Format.dateText(transaction.postedAt))
                .font(.appCallout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Image(systemName: transaction.kind.systemImage)
                .foregroundStyle(ProMeColor.transfer)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appBody.weight(.medium))
                if let memo = transaction.memo, !memo.isEmpty {
                    Text(memo).font(.appCaption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Format.amount(transaction.amountMinor, code: transaction.currencyCode))
                .font(.appCallout.monospacedDigit().weight(.semibold))
                .frame(width: 160, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        let from = transaction.fromAccount?.name ?? "?"
        let to = transaction.toAccount?.name ?? "?"
        let suffix: String
        switch transaction.kind {
        case .ownerContribution: suffix = " · " + String(localized: "Owner Contribution")
        case .ownerWithdrawal: suffix = " · " + String(localized: "Owner Withdrawal")
        default: suffix = ""
        }
        return "\(from) → \(to)\(suffix)"
    }
}

struct TransferEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var date = Date()
    @State private var from: MoneyAccountMO?
    @State private var to: MoneyAccountMO?
    @State private var memo = ""
    @State private var accounts: [MoneyAccountMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var inlineAccountSheet = false
    @State private var inlineTarget: InlineTarget = .from

    private enum InlineTarget {
        case from
        case to
    }

    private var crossScope: Bool {
        guard let from, let to else { return false }
        return from.scope?.objectID != to.scope?.objectID
    }

    private var relationLabel: String? {
        guard crossScope, let from, let to else { return nil }
        let personalFirst = from.scope?.kind == .personal
        return personalFirst
            ? String(localized: "Will be recorded as Owner Contribution.")
            : String(localized: "Will be recorded as Owner Withdrawal.")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                AmountField(title: String(localized: "Amount"), currencyCode: from?.currencyCode ?? AppPreferences.baseCurrency.code, text: $amountText)

                AccountPicker(title: String(localized: "From"), selection: $from, accounts: accounts, onNewAccount: {
                    inlineTarget = .from
                    inlineAccountSheet = true
                })
                AccountPicker(title: String(localized: "To"), selection: $to, accounts: accounts, onNewAccount: {
                    inlineTarget = .to
                    inlineAccountSheet = true
                })
                DatePicker(String(localized: "Date"), selection: $date, displayedComponents: .date)
                TextField(String(localized: "Description"), text: $memo)

                if let relationLabel {
                    Label(relationLabel, systemImage: "person.2")
                        .font(.appCallout)
                        .foregroundStyle(ProMeColor.transfer)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Transfer"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(from == nil || to == nil)
            }
            .padding()
        }
        .onAppear(perform: load)
        .sheet(isPresented: $inlineAccountSheet) {
            AccountEditor(account: nil, onCreated: { created in
                if !accounts.contains(where: { $0.objectID == created.objectID }) {
                    accounts.append(created)
                }
                switch inlineTarget {
                case .from: from = created
                case .to: to = created
                }
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
        from = accounts.first
        to = accounts.count > 1 ? accounts[1] : nil
    }

    private func save() {
        guard let services = appModel.services else { return }
        guard let from, let to else { return }
        guard let minor = MoneyInput.parseMinorUnits(amountText, currency: from.currency) else {
            errorMessage = String(localized: "Enter a valid amount.")
            return
        }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if from.scope?.kind == .personal, to.scope?.kind == .business {
                _ = try services.posting.postOwnerContribution(
                    from: from, to: to, amountMinor: minor, date: date,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo
                )
            } else if from.scope?.kind == .business, to.scope?.kind == .personal {
                _ = try services.posting.postOwnerWithdrawal(
                    from: from, to: to, amountMinor: minor, date: date,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo
                )
            } else {
                _ = try services.posting.postTransfer(
                    from: from, to: to, amountMinor: minor, date: date,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo
                )
            }
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
