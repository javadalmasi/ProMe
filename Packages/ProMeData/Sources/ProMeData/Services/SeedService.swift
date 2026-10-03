import CoreData
import Foundation
import ProMeDomain

/// First-launch seeding: Personal scope plus the default Persian category
/// tree (global categories shared by all scopes).
@MainActor
public final class SeedService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    private var context: NSManagedObjectContext { controller.container.viewContext }

    public struct SeedCategory {
        public let name: String
        public let kind: CategoryKind
        public let children: [String]

        public init(_ name: String, _ kind: CategoryKind, children: [String] = []) {
            self.name = name
            self.kind = kind
            self.children = children
        }
    }

    public static let defaultCategories: [SeedCategory] = [
        SeedCategory("خوراک", .expense, children: ["رستوران", "سوپرمارکت", "سفارش غذا"]),
        SeedCategory("حمل‌ونقل", .expense, children: ["بنزین", "تاکسی و اسنپ", "تعمیر خودرو"]),
        SeedCategory("مسکن", .expense, children: ["اجاره", "قبض‌ها", "تعمیرات"]),
        SeedCategory("سلامت", .expense, children: ["پزشک", "دارو", "آزمایش"]),
        SeedCategory("بیمه", .expense, children: ["بیمه تکمیلی", "بیمه خودرو"]),
        SeedCategory("خرید", .expense, children: ["لباس", "لوازم الکترونیکی", "لوازم خانه"]),
        SeedCategory("سرگرمی", .expense),
        SeedCategory("آموزش", .expense),
        SeedCategory("سفر", .expense),
        SeedCategory("مالیات", .expense),
        SeedCategory("متفرقه", .expense),
        SeedCategory("حقوق", .income),
        SeedCategory("درآمد کسب‌وکار", .income),
        SeedCategory("فروش", .income),
        SeedCategory("مشاوره", .income),
        SeedCategory("سرمایه‌گذاری", .income),
        SeedCategory("سود بانکی", .income),
        SeedCategory("بازگشت پرداخت", .income),
        SeedCategory("متفرقه", .income),
    ]

    /// Seeds on first run; safe to call on every launch.
    public func runIfNeeded() throws {
        let request = CategoryMO.fetchRequest()
        request.fetchLimit = 1
        let hasCategories = try context.count(for: request) > 0

        let scopeRequest = FinancialScopeMO.fetchRequest()
        scopeRequest.predicate = NSPredicate(format: "kindRaw == %@", ScopeKind.personal.rawValue)
        scopeRequest.fetchLimit = 1
        let hasPersonal = try context.count(for: scopeRequest) > 0

        guard !hasCategories || !hasPersonal else { return }

        if !hasPersonal {
            let scope = FinancialScopeMO(context: context)
            scope.id = UUID()
            scope.name = "شخصی"
            scope.kind = .personal
            scope.isActive = true
            scope.createdAt = .now
        }

        if !hasCategories {
            for seed in Self.defaultCategories {
                let category = CategoryMO(context: context)
                category.id = UUID()
                category.name = seed.name
                category.kind = seed.kind
                category.isSystem = true
                category.createdAt = .now
                category.ledgerAccount = try AccountRepository.ensureLedgerAccount(
                    code: seed.kind == .income
                        ? ChartOfAccounts.incomeCategoryCode(forCategoryID: category.id)
                        : ChartOfAccounts.expenseCategoryCode(forCategoryID: category.id),
                    name: seed.name,
                    type: seed.kind == .income ? .income : .expense,
                    normalSide: seed.kind == .income ? .credit : .debit,
                    in: context
                )
                for childName in seed.children {
                    let child = CategoryMO(context: context)
                    child.id = UUID()
                    child.name = childName
                    child.kind = seed.kind
                    child.isSystem = true
                    child.createdAt = .now
                    child.parent = category
                    child.ledgerAccount = try AccountRepository.ensureLedgerAccount(
                        code: seed.kind == .income
                            ? ChartOfAccounts.incomeCategoryCode(forCategoryID: child.id)
                            : ChartOfAccounts.expenseCategoryCode(forCategoryID: child.id),
                        name: childName,
                        type: seed.kind == .income ? .income : .expense,
                        normalSide: seed.kind == .income ? .credit : .debit,
                        in: context
                    )
                }
            }
        }

        try controller.saveViewContext()
    }
}
