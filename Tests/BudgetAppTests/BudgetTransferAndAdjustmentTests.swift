import XCTest
import SwiftData
@testable import BudgetApp

/// 预算转移、手动调整与台账（规格第九、十八节）。
final class BudgetTransferAndAdjustmentTests: ServiceTestCase {

    // 餐饮 500、娱乐 300，餐饮→娱乐 100 → 400 / 400
    func testTransferMovesRemaining() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500)
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 300)
        try months.ensureMonthlyBudget(for: m)

        try budgets.transfer(
            fromCategoryID: dining.categoryID,
            toCategoryID: fun.categoryID,
            cents: 10000,
            month: m
        )

        XCTAssertEqual(try months.item(categoryID: dining.categoryID, month: m)?.adjustedCents, 40000)
        XCTAssertEqual(try months.item(categoryID: fun.categoryID, month: m)?.adjustedCents, 40000)

        let transferRecords = try context.fetch(FetchDescriptor<BudgetTransfer>())
        XCTAssertEqual(transferRecords.count, 1)
        XCTAssertEqual(transferRecords.first?.cents, 10000)
        XCTAssertEqual(transferRecords.first?.fromCategoryID, dining.categoryID)
        XCTAssertEqual(transferRecords.first?.toCategoryID, fun.categoryID)
    }

    // 转移要留下双向台账（规格第十八节）
    func testTransferWritesBothLedgerEntries() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500)
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 300)
        try months.ensureMonthlyBudget(for: m)

        try budgets.transfer(
            fromCategoryID: dining.categoryID,
            toCategoryID: fun.categoryID,
            cents: 10000,
            month: m
        )

        let ledger = try context.fetch(FetchDescriptor<BudgetAdjustment>())
            .filter { $0.type == .transferIn || $0.type == .transferOut }
        XCTAssertEqual(ledger.count, 2)
        let out = ledger.first { $0.type == .transferOut }
        let inLedger = ledger.first { $0.type == .transferIn }
        XCTAssertEqual(out?.cents, -10000)
        XCTAssertEqual(out?.categoryID, dining.categoryID)
        XCTAssertEqual(inLedger?.cents, 10000)
        XCTAssertEqual(inLedger?.categoryID, fun.categoryID)
    }

    func testTransferExceedingRemainingIsRejected() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500)
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 300)
        try months.ensureMonthlyBudget(for: m)

        XCTAssertThrowsError(
            try budgets.transfer(
                fromCategoryID: dining.categoryID,
                toCategoryID: fun.categoryID,
                cents: 60000,
                month: m
            )
        )
        XCTAssertEqual(try months.item(categoryID: dining.categoryID, month: m)?.adjustedCents, 50000)
    }

    // 已花掉的部分不能被转走：花 470 剩 30，想转 100 应被拒绝
    func testTransferCannotMoveSpentMoney() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500)
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 300)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 47000, description: "聚餐",
            categoryID: dining.categoryID, date: date(2026, 8, 8)
        )

        XCTAssertThrowsError(
            try budgets.transfer(
                fromCategoryID: dining.categoryID,
                toCategoryID: fun.categoryID,
                cents: 10000,
                month: m
            )
        )
    }

    func testTransferToSameCategoryIsRejected() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500)
        try months.ensureMonthlyBudget(for: m)

        XCTAssertThrowsError(
            try budgets.transfer(
                fromCategoryID: dining.categoryID,
                toCategoryID: dining.categoryID,
                cents: 100,
                month: m
            )
        )
    }

    // 初始化要写台账：餐饮 +1200，原因「本月预算初始化」（规格第十八节示例）
    func testInitialAllocationWritesLedger() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1200)
        try months.ensureMonthlyBudget(for: m)

        let ledger = try context.fetch(FetchDescriptor<BudgetAdjustment>())
            .filter { $0.categoryID == dining.categoryID && $0.type == .initial }
        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger.first?.cents, 120000)
        XCTAssertEqual(ledger.first?.reason, "本月预算初始化")
    }

    // 手动增加 200：余额与已分配同步变化，并留下台账
    func testManualAdjustmentUpdatesBudgetAndLedger() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        let budget = try months.ensureMonthlyBudget(for: m)

        try budgets.adjustBudget(
            categoryID: dining.categoryID,
            month: m,
            deltaCents: 20000,
            reason: "手动增加预算"
        )

        XCTAssertEqual(try months.item(categoryID: dining.categoryID, month: m)?.adjustedCents, 120000)
        XCTAssertEqual(budget.allocatedCents, 120000)
        let manual = try context.fetch(FetchDescriptor<BudgetAdjustment>())
            .filter { $0.type == .manual }
        XCTAssertEqual(manual.count, 1)
        XCTAssertEqual(manual.first?.cents, 20000)
    }

    // 分配页把初始 1000 改成 800 → 剩余 800，已分配 800
    func testSetInitialAllocation() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        let budget = try months.ensureMonthlyBudget(for: m)

        try budgets.setInitialAllocation(categoryID: dining.categoryID, month: m, cents: 80000)

        let item = try months.item(categoryID: dining.categoryID, month: m)
        XCTAssertEqual(item?.initialCents, 80000)
        XCTAssertEqual(item?.adjustedCents, 80000)
        XCTAssertEqual(budget.allocatedCents, 80000)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 80000)
    }

    // 转移不改变本月已分配总额
    func testTransferDoesNotChangeAllocatedTotal() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 500)
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 300)
        let budget = try months.ensureMonthlyBudget(for: m)

        try budgets.transfer(
            fromCategoryID: dining.categoryID,
            toCategoryID: fun.categoryID,
            cents: 10000,
            month: m
        )

        XCTAssertEqual(budget.allocatedCents, 80000)
    }
}
