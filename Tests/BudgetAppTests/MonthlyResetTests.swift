import XCTest
import SwiftData
@testable import BudgetApp

/// 月度重置与余额结转（规格第十五、十六节）。
final class MonthlyResetTests: ServiceTestCase {

    func testEnsureMonthlyBudgetIsIdempotent() throws {
        let dining = try makeCategory(monthlyYuan: 1000)

        let first = try months.ensureMonthlyBudget(for: m)
        let second = try months.ensureMonthlyBudget(for: m)

        XCTAssertEqual(first.monthlyBudgetID, second.monthlyBudgetID)
        let items = try months.items(in: m)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.categoryID, dining.categoryID)
        XCTAssertEqual(items.first?.adjustedCents, 100000)
    }

    // 本月剩 200，下月基础 500，启用结转 → 下月 700（规格第三十七节）
    func testCarryOverSumsIntoNextMonth() throws {
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 500, carryOver: true)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 30000, description: "电影票",
            categoryID: fun.categoryID, date: date(2026, 8, 21)
        )

        try months.ensureMonthlyBudget(for: sep)

        let sepItem = try months.item(categoryID: fun.categoryID, month: sep)
        XCTAssertEqual(sepItem?.adjustedCents, 70000)
        XCTAssertEqual(sepItem?.carryOverCents, 20000)
        // 上月数据不被破坏
        XCTAssertEqual(try months.remainingCents(categoryID: fun.categoryID, month: m), 20000)
    }

    // 不结转的分区下月回到固定预算
    func testCarryOverDisabledResetsToBase() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500, carryOver: false)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 30000, description: "外卖",
            categoryID: dining.categoryID, date: date(2026, 8, 21)
        )

        try months.ensureMonthlyBudget(for: sep)

        let sepItem = try months.item(categoryID: dining.categoryID, month: sep)
        XCTAssertEqual(sepItem?.adjustedCents, 50000)
        XCTAssertEqual(sepItem?.carryOverCents, 0)
    }

    // 超支的负数不结转：上月 -50，下月仍是固定预算 500
    func testNegativeRemainingDoesNotCarry() throws {
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 500, carryOver: true)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 55000, description: "游戏机",
            categoryID: fun.categoryID, date: date(2026, 8, 21)
        )

        try months.ensureMonthlyBudget(for: sep)

        let sepItem = try months.item(categoryID: fun.categoryID, month: sep)
        XCTAssertEqual(sepItem?.adjustedCents, 50000)
        XCTAssertEqual(sepItem?.carryOverCents, 0)
    }

    // 储蓄类分区（结转开启）逐月累积
    func testSavingCategoryAccumulates() throws {
        let saving = try makeCategory(name: "储蓄", monthlyYuan: 1000, carryOver: true, saving: true)
        try months.ensureMonthlyBudget(for: m)
        try months.ensureMonthlyBudget(for: sep)

        let sepItem = try months.item(categoryID: saving.categoryID, month: sep)
        XCTAssertEqual(sepItem?.adjustedCents, 200000)
    }

    // 结转不算新分配：下月已分配只含基础预算
    func testCarryOverDoesNotCountAsAllocation() throws {
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 500, carryOver: true)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 30000, description: "电影票",
            categoryID: fun.categoryID, date: date(2026, 8, 21)
        )

        let sepBudget = try months.ensureMonthlyBudget(for: sep)

        XCTAssertEqual(sepBudget.allocatedCents, 50000)
    }

    // 结转要写台账（规格第十八节）
    func testCarryOverWritesLedger() throws {
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 500, carryOver: true)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 30000, description: "电影票",
            categoryID: fun.categoryID, date: date(2026, 8, 21)
        )

        try months.ensureMonthlyBudget(for: sep)

        let carryLedger = try context.fetch(FetchDescriptor<BudgetAdjustment>())
            .filter { $0.type == .carryOver && $0.month == 9 }
        XCTAssertEqual(carryLedger.count, 1)
        XCTAssertEqual(carryLedger.first?.cents, 20000)
    }

    // 月中新建分区（此前月份没建过预算项）：直接按默认金额生成，无结转
    func testMidMonthNewCategoryGetsDefaultBudget() throws {
        try months.ensureMonthlyBudget(for: m)
        let travel = try makeCategory(name: "旅行", monthlyYuan: 200)

        let item = try months.ensureItem(categoryID: travel.categoryID, month: m)

        XCTAssertEqual(item.adjustedCents, 20000)
        XCTAssertEqual(item.initialCents, 20000)
        XCTAssertEqual(item.carryOverCents, 0)
    }

    // 隐藏分区不参与月度生成
    func testHiddenCategorySkippedInMonthlyCreation() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        try budgets.setCategoryHidden(dining, hidden: true)

        try months.ensureMonthlyBudget(for: m)

        let items = try months.items(in: m)
        XCTAssertTrue(items.isEmpty)
    }
}
