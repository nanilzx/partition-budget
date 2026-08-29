import XCTest
import SwiftData
@testable import BudgetApp

/// 规格第三十七节核心场景：消费扣减、删除恢复、修改差值、修改分类、超支、月度隔离。
final class TransactionBudgetTests: ServiceTestCase {

    // 预算 1000，消费 100 → 剩余 900
    func testAddExpenseDeductsBudget() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)

        try transactions.addExpense(
            cents: 10000, description: "麦当劳",
            categoryID: dining.categoryID, date: date(2026, 8, 15)
        )

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 90000)
        XCTAssertEqual(try months.spentCents(categoryID: dining.categoryID, month: m), 10000)
    }

    // 余额 900，删除 100 的消费 → 1000
    func testDeleteExpenseRestoresBudget() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)
        let txn = try transactions.addExpense(
            cents: 10000, description: "麦当劳",
            categoryID: dining.categoryID, date: date(2026, 8, 15)
        )

        try transactions.delete(txn)

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 100000)
        XCTAssertEqual(try months.monthTransactions(m).count, 0)
    }

    // 消费 100 改为 150 → 预算额外减少 50
    func testEditExpenseAmountAdjustsByDelta() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)
        let txn = try transactions.addExpense(
            cents: 10000, description: "晚饭",
            categoryID: dining.categoryID, date: date(2026, 8, 10)
        )

        try transactions.update(txn, cents: 15000)

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 85000)
    }

    // 餐饮 -100 改到娱乐 → 餐饮 +100，娱乐 -100
    func testEditCategoryMovesBudgetBetweenCategories() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 500)
        try months.ensureMonthlyBudget(for: m)
        let txn = try transactions.addExpense(
            cents: 10000, description: "手办",
            categoryID: dining.categoryID, date: date(2026, 8, 10)
        )

        try transactions.update(txn, categoryID: fun.categoryID)

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 100000)
        XCTAssertEqual(try months.remainingCents(categoryID: fun.categoryID, month: m), 40000)
        XCTAssertTrue(txn.isUserCorrected)
        XCTAssertEqual(txn.classificationSource, .manual)
    }

    // 8 月 31 日改为 9 月 1 日 → 8 月恢复，9 月扣除
    func testEditDateMovesTransactionAcrossMonths() throws {
        let dining = try makeCategory(monthlyYuan: 500)
        try months.ensureMonthlyBudget(for: m)
        let txn = try transactions.addExpense(
            cents: 10000, description: "晚饭",
            categoryID: dining.categoryID, date: date(2026, 8, 31)
        )

        try transactions.update(txn, date: date(2026, 9, 1))

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 50000)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: sep), 40000)
    }

    // 预算 50，消费 80 → 允许，余额 -30
    func testOverdraftAllowedBalanceGoesNegative() throws {
        let dining = try makeCategory(monthlyYuan: 50)
        try months.ensureMonthlyBudget(for: m)

        try transactions.addExpense(
            cents: 8000, description: "夜宵",
            categoryID: dining.categoryID, date: date(2026, 8, 20)
        )

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), -3000)
    }

    func testMultipleExpensesAccumulate() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)

        try transactions.addExpense(cents: 2350, description: "美团外卖", categoryID: dining.categoryID, date: date(2026, 8, 1))
        try transactions.addExpense(cents: 3600, description: "麦当劳", categoryID: dining.categoryID, date: date(2026, 8, 5))
        try transactions.addExpense(cents: 1200, description: "瑞幸", categoryID: dining.categoryID, date: date(2026, 8, 9))

        XCTAssertEqual(try months.spentCents(categoryID: dining.categoryID, month: m), 7150)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 92850)
    }

    // 不同月份的数据必须完全隔离
    func testMonthDataIsSeparated() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)
        try months.ensureMonthlyBudget(for: sep)

        try transactions.addExpense(
            cents: 30000, description: "聚餐",
            categoryID: dining.categoryID, date: date(2026, 8, 12)
        )

        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 70000)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: sep), 100000)
    }

    func testIncomeDoesNotAffectBudget() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)

        try transactions.addIncome(cents: 650000, description: "工资", date: date(2026, 8, 1))

        XCTAssertEqual(try months.incomeCents(month: m), 650000)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 100000)
    }

    func testInvalidAmountIsRejected() throws {
        let dining = try makeCategory(monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)

        XCTAssertThrowsError(
            try transactions.addExpense(
                cents: 0, description: "无效",
                categoryID: dining.categoryID, date: date(2026, 8, 5)
            )
        )
        XCTAssertEqual(try months.monthTransactions(m).count, 0)
    }
}
