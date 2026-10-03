import CoreData
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// Bank CSV import wizard: pick a file, map columns with a live preview,
/// choose the target account/categories, review duplicates, import.
struct ImportWizardView: View {
    enum Step: Int, CaseIterable {
        case file = 0
        case mapping = 1
        case target = 2
        case done = 3
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .file
    @State private var cells: [[String]] = []
    @State private var mapping = ImportService.Mapping()
    @State private var accounts: [MoneyAccountMO] = []
    @State private var categories: [CategoryMO] = []
    @State private var account: MoneyAccountMO?
    @State private var incomeCategory: CategoryMO?
    @State private var expenseCategory: CategoryMO?
    @State private var skipDuplicates = true
    @State private var drafts: [ImportService.DraftRow] = []
    @State private var result: ImportService.ImportResult?
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            stepHeader

            Group {
                switch step {
                case .file: fileStep
                case .mapping: mappingStep
                case .target: targetStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .onAppear(perform: load)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { outcome in
            guard case .success(let urls) = outcome, let url = urls.first else { return }
            loadFile(url: url)
        }
        .alert(String(localized: "Cannot Import"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Steps

    private var stepHeader: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                let index = Step.allCases.firstIndex(of: item) ?? 0
                Circle()
                    .fill(step.rawValue >= item.rawValue ? ProMeColor.transfer : Color.gray.opacity(0.3))
                    .frame(width: 9, height: 9)
                if index < Step.allCases.count - 1 {
                    Rectangle().fill(.quaternary).frame(width: 34, height: 1.5)
                }
            }
            Spacer()
            Text(stepTitle)
                .font(.appCallout.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepTitle: String {
        switch step {
        case .file: String(localized: "Choose File")
        case .mapping: String(localized: "Map Columns")
        case .target: String(localized: "Target & Review")
        case .done: String(localized: "Done")
        }
    }

    private var fileStep: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                systemImage: "square.and.arrow.down.on.square",
                title: String(localized: "Import from CSV"),
                detail: String(localized: "Pick a bank statement CSV; the app maps its columns, flags duplicates and posts everything through the ledger.")
            )
            Button(String(localized: "Choose File…")) {
                showFilePicker = true
            }
            .buttonStyle(.borderedProminent)
            if !cells.isEmpty {
                Text(String(localized: "\(cells.count) rows found"))
                    .font(.appCallout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var mappingStep: some View {
        Form {
            Toggle(String(localized: "First Row Is Header"), isOn: Binding(
                get: { mapping.hasHeader },
                set: { mapping.hasHeader = $0 }
            ))
            columnPicker(String(localized: "Date"), Binding<Int?>(
                get: { mapping.dateColumn },
                set: { if let value = $0 { mapping.dateColumn = value } }
            ))
            columnPicker(String(localized: "Description"), Binding(
                get: { mapping.descriptionColumn },
                set: { mapping.descriptionColumn = $0 }
            ))
            Picker(String(localized: "Amount Mode"), selection: Binding(
                get: { mapping.amountColumn != nil ? 0 : 1 },
                set: { newValue in
                    if newValue == 0 {
                        mapping.amountColumn = mapping.amountColumn ?? 2
                        mapping.debitColumn = nil
                        mapping.creditColumn = nil
                    } else {
                        mapping.amountColumn = nil
                        mapping.debitColumn = mapping.debitColumn ?? 2
                        mapping.creditColumn = mapping.creditColumn ?? 3
                    }
                }
            )) {
                Text(String(localized: "Single Amount Column")).tag(0)
                Text(String(localized: "Debit & Credit Columns")).tag(1)
            }
            if mapping.amountColumn != nil {
                columnPicker(String(localized: "Amount"), Binding(
                    get: { mapping.amountColumn },
                    set: { mapping.amountColumn = $0 }
                ))
            } else {
                columnPicker(String(localized: "Debit"), Binding(
                    get: { mapping.debitColumn },
                    set: { mapping.debitColumn = $0 }
                ))
                columnPicker(String(localized: "Credit"), Binding(
                    get: { mapping.creditColumn },
                    set: { mapping.creditColumn = $0 }
                ))
            }
            columnPicker(String(localized: "Reference"), Binding(
                get: { mapping.referenceColumn },
                set: { mapping.referenceColumn = $0 }
            ))

            previewTable
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var previewTable: some View {
        let preview = mappingPreviewRows
        if !preview.isEmpty {
            Text(String(localized: "Preview"))
                .font(.appHeadline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(preview.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.appCaption.monospacedDigit())
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
    }

    private var targetStep: some View {
        Form {
            Picker(String(localized: "Account"), selection: $account) {
                Text(String(localized: "Choose…")).tag(MoneyAccountMO?.none)
                ForEach(accounts, id: \.objectID) { item in
                    Label(item.name, systemImage: item.type.systemImage)
                        .tag(MoneyAccountMO?.some(item))
                }
            }
            Picker(String(localized: "Income Category"), selection: $incomeCategory) {
                Text(String(localized: "None")).tag(CategoryMO?.none)
                ForEach(categories.filter { $0.kind == .income }, id: \.objectID) { category in
                    Text(category.name).tag(CategoryMO?.some(category))
                }
            }
            Picker(String(localized: "Expense Category"), selection: $expenseCategory) {
                Text(String(localized: "Choose…")).tag(CategoryMO?.none)
                ForEach(categories.filter { $0.kind == .expense }, id: \.objectID) { category in
                    Text(category.name).tag(CategoryMO?.some(category))
                }
            }
            Toggle(String(localized: "Skip Duplicates"), isOn: $skipDuplicates)
            if drafts.filter({ $0.isDuplicate }).count > 0 {
                Label(
                    String(localized: "\(drafts.filter { $0.isDuplicate }.count) possible duplicates found"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.appCallout)
                .foregroundStyle(.orange)
            }
            LabeledContent(String(localized: "Rows Ready"), value: "\(drafts.count)")
        }
        .formStyle(.grouped)
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            if let result {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(ProMeColor.income)
                Text(String(localized: "Import Finished"))
                    .font(.appTitle3.weight(.semibold))
                LabeledContent(String(localized: "Imported"), value: "\(result.imported)")
                LabeledContent(String(localized: "Skipped Duplicates"), value: "\(result.skippedDuplicates)")
                if result.failedRows > 0 {
                    LabeledContent(String(localized: "Failed Rows"), value: "\(result.failedRows)")
                        .foregroundStyle(ProMeColor.expense)
                }
            }
        }
        .padding(24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .file && step != .done {
                Button(String(localized: "Back")) {
                    step = Step(rawValue: step.rawValue - 1) ?? .file
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button(String(localized: "Close"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if step == .file {
                Button(String(localized: "Next"), action: prepareMapping)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cells.isEmpty)
            } else if step == .mapping {
                Button(String(localized: "Next"), action: prepareTarget)
                    .keyboardShortcut(.defaultAction)
            } else if step == .target {
                Button(String(localized: "Import"), action: runImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(account == nil || expenseCategory == nil || drafts.isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Logic

    private var mappingPreviewRows: [String] {
        let body = mapping.hasHeader ? Array(cells.dropFirst()) : cells
        return body.prefix(5).map { line in
            var parts: [String] = []
            if mapping.dateColumn < line.count {
                parts.append(Self.parseDatePreview(line[mapping.dateColumn]))
            }
            if let amountColumn = mapping.amountColumn, amountColumn < line.count {
                parts.append(line[amountColumn])
            }
            if let debit = mapping.debitColumn, debit < line.count {
                parts.append("D:\(line[debit])")
            }
            if let credit = mapping.creditColumn, credit < line.count {
                parts.append("C:\(line[credit])")
            }
            if let descriptionColumn = mapping.descriptionColumn, descriptionColumn < line.count {
                parts.append(line[descriptionColumn])
            }
            return parts.joined(separator: "  |  ")
        }
    }

    private static func parseDatePreview(_ raw: String) -> String {
        ImportService.parseDate(raw).map { Format.dateText($0) } ?? "⚠︎ \(raw)"
    }

    private func columnPicker(_ title: String, _ binding: Binding<Int?>) -> some View {
        Picker(title, selection: binding) {
            Text(String(localized: "None")).tag(Int?.none)
            ForEach(0..<maxColumnCount, id: \.self) { index in
                Text(columnTitle(index)).tag(Int?.some(index))
            }
        }
    }

    private var maxColumnCount: Int {
        cells.map(\.count).max() ?? 0
    }

    private func columnTitle(_ index: Int) -> String {
        let header = mapping.hasHeader ? cells.first : nil
        let name: String = header.flatMap { headerRow -> String? in
            index < headerRow.count ? headerRow[index] : nil
        } ?? ""
        let scalar = 65 + index
        let letter: String
        if let unicode = UnicodeScalar(scalar) {
            letter = String(Character(unicode))
        } else {
            letter = "?"
        }
        if name.isEmpty {
            return letter
        }
        return letter + " · " + name
    }

    private func load() {
        guard !loaded, let services = appModel.services else { return }
        loaded = true
        accounts = (try? services.accounts.allAccounts()) ?? []
        categories = (try? services.categories.allCategories()) ?? []
        account = accounts.first
        expenseCategory = categories.first { $0.kind == .expense && $0.name == "متفرقه" }
            ?? categories.first { $0.kind == .expense }
    }

    private func loadFile(url: URL) {
        do {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            cells = CSVParser.parse(text)
            step = .mapping
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }

    private func prepareMapping() {
        step = .mapping
    }

    private func prepareTarget() {
        guard let services = appModel.services, let account else { return }
        do {
            drafts = try services.importService.draftRows(cells: cells, mapping: mapping, currency: account.currency)
            try services.importService.flagDuplicates(account: account, drafts: &drafts)
            step = .target
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }

    private func runImport() {
        guard let services = appModel.services, let account, let expenseCategory else { return }
        guard let scope = appModel.activeScope ?? account.scope ?? appModel.personalScope else { return }
        do {
            result = try services.importService.import(
                drafts: drafts, scope: scope, account: account,
                incomeCategory: incomeCategory, expenseCategory: expenseCategory,
                skipDuplicates: skipDuplicates
            )
            appModel.bumpData()
            step = .done
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
