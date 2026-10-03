import ProMeDesignSystem
import SwiftUI

/// Two-column shell: custom sidebar plus the selected detail screen.
/// Selection animates with a shared sliding pill; route changes cross-fade.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .sheet(isPresented: $appModel.quickEntryPresented) {
            QuickEntryView()
                .frame(minWidth: 420, minHeight: 380)
        }
        .sheet(item: $appModel.presentedSheet, onDismiss: { appModel.bumpData() }) { sheet in
            switch sheet {
            case .transfer:
                TransferEditor()
                    .frame(minWidth: 420, minHeight: 330)
            case .account:
                AccountEditor(account: nil)
                    .frame(minWidth: 440, minHeight: 430)
            case .category:
                CategoryEditor(kind: .expense, category: nil)
                    .frame(minWidth: 380, minHeight: 260)
            case .business:
                BusinessEditor()
                    .frame(minWidth: 400, minHeight: 280)
            case .debt:
                DebtEditor(direction: .receivable)
                    .frame(minWidth: 420, minHeight: 340)
            case .loan:
                LoanEditor()
                    .frame(minWidth: 440, minHeight: 430)
            case .insurance:
                InsuranceEditor()
                    .frame(minWidth: 440, minHeight: 460)
            case .task:
                TaskEditor()
                    .frame(minWidth: 420, minHeight: 480)
            case .appointment:
                AppointmentEditor()
                    .frame(minWidth: 440, minHeight: 540)
            case .note:
                NoteEditor()
                    .frame(minWidth: 480, minHeight: 480)
            case .alert:
                AlertEditor()
                    .frame(minWidth: 420, minHeight: 430)
            }
        }
        .sheet(isPresented: $appModel.showShortcuts) {
            ShortcutsHelpView()
                .frame(minWidth: 480, minHeight: 500)
        }
        .sheet(isPresented: $appModel.showSettings) {
            SettingsView()
                .environment(appModel)
        }
        .font(.appBody)
        .tint(.accentColor)
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var appModel
    @Namespace private var selectionPill
    @State private var appeared = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ProMeSpacing.large) {
                    brandHeader
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onAppear {
                proxy.scrollTo(appModel.selectedRoute, anchor: .center)
            }
        }
        .navigationTitle("ProMe")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 300)
        #endif
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.05)) {
                appeared = true
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color.indigo, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("ProMe").font(.appTitle3.weight(.bold))
                Text(String(localized: "Your personal command center"))
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
    }

    @ViewBuilder
    private func sectionView(_ section: SidebarSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(section.title).font(.appCaption.weight(.semibold))
            } icon: {
                Image(systemName: section.systemImage)
                    .font(.appCaption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            ForEach(Array(section.routes.enumerated()), id: \.element) { index, route in
                sidebarRow(route)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.85)
                            .delay(0.03 * Double(index)),
                        value: appeared
                    )
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ route: AppRoute) -> some View {
        let isSelected = appModel.selectedRoute == route
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                appModel.selectedRoute = route
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: route.systemImage)
                    .font(.appCallout.weight(.medium))
                    .frame(width: 20)
                    .symbolVariant(isSelected ? .fill : .none)
                Text(route.title)
                    .font(.appCallout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "route-pill", in: selectionPill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(route)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let launchError = appModel.launchError {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: String(localized: "Could not open the database"),
                    detail: launchError.localizedDescription
                )
            } else {
                switch appModel.selectedRoute {
                case .dashboard: DashboardView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                case .appointments: AppointmentsView()
                case .alertsActivities: AlertsActivitiesView()
                case .notes: NotesView()
                case .places: PlacesView()
                case .transactions: TransactionsView()
                case .accounts: AccountsView()
                case .transfers: TransfersView()
                case .debts: DebtsView()
                case .loans: LoansView()
                case .insurance: InsuranceView()
                case .assets: AssetsView()
                case .categories: CategoriesView()
                case .budgets: BudgetsView()
                case .recurring: RecurringView()
                case .businesses: BusinessesView()
                case .reports: ReportsView()
                }
            }
        }
        .id(appModel.selectedRoute)
        .transition(.opacity.combined(with: .scale(scale: 0.995)))
        .animation(.snappy(duration: 0.22), value: appModel.selectedRoute)
        .toolbar { mainToolbar }
    }

    /// Scope picker + Quick Entry, shown on every screen.
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                appModel.showSettings = true
            } label: {
                Label(String(localized: "Settings"), systemImage: "gearshape")
            }
        }
        #endif
        ToolbarItemGroup(placement: .primaryAction) {
            ScopePicker()
            Button {
                appModel.quickEntryPresented = true
            } label: {
                Label(String(localized: "New Transaction"), systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

/// Personal / each business / all.
struct ScopePicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Picker(String(localized: "Scope"), selection: Binding(
            get: { appModel.scopeSelection },
            set: { appModel.scopeSelection = $0 }
        )) {
            Text(String(localized: "All")).tag(ScopeSelection.all)
            ForEach(appModel.scopesList, id: \.objectID) { scope in
                Text(scope.name).tag(ScopeSelection.scope(scope.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 180)
    }
}
