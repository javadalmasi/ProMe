import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Two-level category tree management with a delete guard that protects
/// financial history.
struct CategoriesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var kind: CategoryKind = .expense
    @State private var roots: [CategoryMO] = []
    @State private var editing: CategoryMO?
    @State private var showNew = false
    @State private var confirmDelete: CategoryMO?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Kind"), selection: $kind) {
                Text(String(localized: "Expense")).tag(CategoryKind.expense)
                Text(String(localized: "Income")).tag(CategoryKind.income)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if roots.isEmpty {
                EmptyStateView(
                    systemImage: "tag",
                    title: String(localized: "No Categories"),
                    detail: String(localized: "Add a category to organize this kind.")
                )
            } else {
                List {
                    ForEach(roots, id: \.objectID) { root in
                        OutlineGroup([root] + sortedChildren(root), children: \.virtualChildren) { category in
                            categoryRow(category)
                        }
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Categories"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: {
                    Label(String(localized: "New Category"), systemImage: "plus")
                }
            }
        }
        .task(id: "\(kind)-\(appModel.dataEpoch)") { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $showNew, onDismiss: { reload() }) {
            CategoryEditor(kind: kind, category: nil)
                .frame(minWidth: 380, minHeight: 260)
        }
        .sheet(item: $editing, onDismiss: { reload() }) { category in
            CategoryEditor(kind: kind, category: category)
                .frame(minWidth: 380, minHeight: 260)
        }
        .confirmationDialog(
            String(localized: "Delete this category?"),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) { deleteCategory() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Categories with transactions cannot be deleted."))
        }
        .alert(String(localized: "Something went wrong"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func categoryRow(_ category: CategoryMO) -> some View {
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(category.kind == .income ? ProMeColor.income : ProMeColor.expense)
                .font(.appCallout)
            Text(category.name)
            if category.isSystem {
                Text(String(localized: "Built-in"))
                    .font(.appCaption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(String(localized: "\(category.transactions.count) transactions"))
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button(String(localized: "Edit")) { editing = category }
            Button(String(localized: "Delete"), role: .destructive) { confirmDelete = category }
        }
    }

    private func sortedChildren(_ parent: CategoryMO) -> [CategoryMO] {
        parent.children.sorted { $0.name < $1.name }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        let all = (try? services.categories.allCategories(kind: kind)) ?? []
        roots = all.filter { $0.parent == nil }
    }

    private func deleteCategory() {
        guard let services = appModel.services, let category = confirmDelete else { return }
        do {
            try services.categories.delete(category)
            reload()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
        confirmDelete = nil
    }
}

private extension CategoryMO {
    /// OutlineGroup needs an optional-children key path.
    var virtualChildren: [CategoryMO]? {
        let children = children.sorted { $0.name < $1.name }
        return children.isEmpty ? nil : children
    }
}

struct CategoryEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let kind: CategoryKind
    let category: CategoryMO?
    var onCreated: ((CategoryMO) -> Void)? = nil

    @State private var name = ""
    @State private var selectedKind: CategoryKind = .expense
    @State private var parent: CategoryMO?
    @State private var parents: [CategoryMO] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(String(localized: "Name"), text: $name)
                if category == nil {
                    Picker(String(localized: "Kind"), selection: $selectedKind) {
                        Text(String(localized: "Expense")).tag(CategoryKind.expense)
                        Text(String(localized: "Income")).tag(CategoryKind.income)
                    }
                    .onChange(of: selectedKind) { _ in parent = nil }
                    Picker(String(localized: "Parent"), selection: $parent) {
                        Text(String(localized: "Top Level")).tag(CategoryMO?.none)
                        ForEach(parents.filter { $0.kind == selectedKind }, id: \.objectID) { item in
                            Text(item.name).tag(CategoryMO?.some(item))
                        }
                    }
                } else {
                    LabeledContent(String(localized: "Kind"), value: category?.kind == .income ? String(localized: "Income") : String(localized: "Expense"))
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
        parents = (try? services.categories.allCategories())?.filter { $0.parent == nil } ?? []
        if let category {
            name = category.name
            selectedKind = category.kind
        } else {
            selectedKind = kind
        }
    }

    private func save() {
        guard let services = appModel.services else { return }
        do {
            if let category {
                try services.categories.rename(category, to: name)
            } else {
                let created = try services.categories.create(name: name, kind: selectedKind, parent: parent)
                onCreated?(created)
            }
            dismiss()
        } catch {
            errorMessage = ProMeLog.record(error)
        }
    }
}
