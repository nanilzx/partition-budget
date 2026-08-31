import XCTest
import SwiftData
@testable import BudgetApp

/// 分区生命周期：创建、重名、删除保护（规格第二节）。
final class CategoryLifecycleTests: ServiceTestCase {

    func testDeleteCategoryWithoutTransactions() throws {
        let travel = try makeCategory(name: "旅行")
        try months.ensureMonthlyBudget(for: m) // 生成当月预算项

        try budgets.deleteCategory(travel)

        XCTAssertEqual(try BudgetCategory.all(in: context).count, 0)
        XCTAssertEqual(try months.items(in: m).count, 0)
    }

    // 有消费记录的分区必须阻止删除，记录不能失效
    func testDeleteCategoryWithTransactionsIsBlocked() throws {
        let dining = try makeCategory(name: "餐饮")
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 10000, description: "麦当劳",
            categoryID: dining.categoryID, date: date(2026, 8, 5)
        )

        XCTAssertThrowsError(try budgets.deleteCategory(dining)) { error in
            guard case ServiceError.categoryInUse = error else {
                return XCTFail("应为 categoryInUse 错误，实际：\(error)")
            }
        }
        XCTAssertEqual(try BudgetCategory.all(in: context).count, 1)
        XCTAssertEqual(try months.monthTransactions(m).count, 1)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 90000)
    }

    func testDeleteCategoryWithSavingGoalIsBlocked() throws {
        let saving = try makeCategory(name: "旅行基金", saving: true)
        _ = try SavingGoalService(context: context).create(
            name: "日本旅行",
            categoryID: saving.categoryID,
            targetCents: Money(yuan: 20_000).cents,
            targetDate: nil
        )

        XCTAssertThrowsError(try budgets.deleteCategory(saving)) { error in
            guard case ServiceError.categoryHasSavingGoals = error else {
                return XCTFail("应为 categoryHasSavingGoals 错误，实际：\(error)")
            }
        }
        XCTAssertEqual(try BudgetCategory.all(in: context).count, 1)
        XCTAssertEqual(try SavingGoal.all(in: context).count, 1)
    }

    func testDuplicateCategoryNameIsRejected() throws {
        _ = try makeCategory(name: "餐饮")

        XCTAssertThrowsError(try makeCategory(name: "餐饮")) { error in
            guard case ServiceError.duplicateName = error else {
                return XCTFail("应为 duplicateName 错误，实际：\(error)")
            }
        }
    }

    func testEmptyNameIsRejected() {
        XCTAssertThrowsError(
            try budgets.createCategory(
                name: "  ", icon: "folder", colorHex: "#000000",
                defaultMonthlyCents: 0, carryOverEnabled: false, isSavingCategory: false
            )
        )
    }

    func testReorderUpdatesSortOrder() throws {
        let a = try makeCategory(name: "交通")
        let b = try makeCategory(name: "餐饮")
        let c = try makeCategory(name: "娱乐")

        try budgets.reorder([c, a, b])

        XCTAssertEqual(a.sortOrder, 1)
        XCTAssertEqual(b.sortOrder, 2)
        XCTAssertEqual(c.sortOrder, 0)
    }

    // 首页汇总：日常预算不含储蓄分区
    func testHomeSummaryExcludesSavingCategories() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        let saving = try makeCategory(name: "储蓄", monthlyYuan: 1400, carryOver: true, saving: true)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 10000, description: "麦当劳",
            categoryID: dining.categoryID, date: date(2026, 8, 5)
        )
        try transactions.addIncome(cents: 650000, description: "工资", date: date(2026, 8, 1))

        let items = try months.items(in: m)
        let monthTxns = try months.monthTransactions(m)
        let budget = try months.monthlyBudget(for: m)

        let summary = HomeCalculator.summarize(
            categories: [dining, saving],
            items: items,
            monthlyBudget: budget,
            transactions: monthTxns
        )

        XCTAssertEqual(summary.totalBudgetCents, 100000)     // 只算日常分区
        XCTAssertEqual(summary.spentCents, 10000)
        XCTAssertEqual(summary.remainingCents, 90000)
        XCTAssertEqual(summary.incomeCents, 650000)
        XCTAssertEqual(summary.allocatedCents, 240000)       // 含储蓄
        XCTAssertEqual(summary.unallocatedCents, 410000)

        let dailyCards = HomeCalculator.cards(
            categories: [dining, saving], items: items, transactions: monthTxns, savingOnly: false
        )
        let savingCards = HomeCalculator.cards(
            categories: [dining, saving], items: items, transactions: monthTxns, savingOnly: true
        )
        XCTAssertEqual(dailyCards.count, 1)
        XCTAssertEqual(dailyCards.first?.status, .normal)
        XCTAssertEqual(savingCards.count, 1)
    }

    // 预算状态阈值（规格第十四节）：剩余 30% 提醒 / 10% 警告 / 负数超支
    func testBudgetStatusThresholds() {
        XCTAssertEqual(HomeCalculator.status(remainingCents: 700, adjustedCents: 1000), .normal)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 301, adjustedCents: 1000), .normal)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 300, adjustedCents: 1000), .notice)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 110, adjustedCents: 1000), .notice)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 100, adjustedCents: 1000), .warning)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 90, adjustedCents: 1000), .warning)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 0, adjustedCents: 1000), .warning)
        XCTAssertEqual(HomeCalculator.status(remainingCents: -50, adjustedCents: 1000), .overspent)
        XCTAssertEqual(HomeCalculator.status(remainingCents: 0, adjustedCents: 0), .unallocated)
    }
}
