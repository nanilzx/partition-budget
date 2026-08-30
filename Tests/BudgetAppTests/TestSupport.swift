import XCTest
import SwiftData
@testable import BudgetApp

/// 财务逻辑测试基类：每个用例独立使用一份内存数据库。
class ServiceTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var months: MonthlyBudgetService!
    var budgets: BudgetService!
    var transactions: TransactionService!
    var accounts: AccountService!
    var classification: ClassificationService!

    let m = BudgetMonth(year: 2026, month: 8)
    let sep = BudgetMonth(year: 2026, month: 9)

    override func setUpWithError() throws {
        let schema = Schema([
            BudgetCategory.self,
            Transaction.self,
            MonthlyBudget.self,
            MonthlyBudgetItem.self,
            BudgetTransfer.self,
            BudgetAdjustment.self,
            ClassificationRule.self,
            Account.self,
            SavingGoal.self,
            CaptureInboxItem.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        context.autosaveEnabled = false
        months = MonthlyBudgetService(context: context)
        budgets = BudgetService(context: context)
        transactions = TransactionService(context: context)
        accounts = AccountService(context: context)
        classification = ClassificationService(context: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        months = nil
        budgets = nil
        transactions = nil
        accounts = nil
        classification = nil
    }

    func makeCategory(
        name: String = "餐饮",
        monthlyYuan: Int64 = 1000,
        carryOver: Bool = false,
        saving: Bool = false
    ) throws -> BudgetCategory {
        try budgets.createCategory(
            name: name,
            icon: "fork.knife",
            colorHex: "#FF0000",
            defaultMonthlyCents: Money(yuan: monthlyYuan).cents,
            carryOverEnabled: carryOver,
            isSavingCategory: saving
        )
    }

    func date(_ year: Int, _ month: Int, _ day: Int = 1, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }
}
