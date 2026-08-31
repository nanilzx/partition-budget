import XCTest
import SwiftData
@testable import BudgetApp

/// 数据备份：全量导出 + 覆盖式导入往返（规格第二十三节）。
final class BackupServiceTests: ServiceTestCase {

    private func seedSampleData() throws -> BudgetCategory {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1200)
        let saving = try makeCategory(name: "储蓄", monthlyYuan: 1400, carryOver: true, saving: true)
        _ = try accounts.create(
            name: "微信零钱", type: .wechat, icon: "iphone",
            openingBalanceCents: Money(yuan: 8000).cents, includeInNetWorth: true
        )
        _ = try SavingGoalService(context: context).create(
            name: "旅行基金",
            categoryID: saving.categoryID,
            targetCents: Money(yuan: 10_000).cents,
            targetDate: date(2027, 8, 1)
        )
        // 一笔转移 + 一笔消费 + 一条规则，覆盖全部导出类型
        try budgets.transfer(
            fromCategoryID: dining.categoryID,
            toCategoryID: saving.categoryID,
            cents: 10000,
            month: m
        )
        try transactions.addExpense(
            cents: 2390, description: "美团外卖", categoryID: dining.categoryID,
            date: date(2026, 8, 10), classificationSource: .builtinRule, confidence: 0.8
        )
        try classification.upsertRule(keyword: "美团外卖", categoryID: dining.categoryID)
        return dining
    }

    func testExportImportRoundTrip() throws {
        let dining = try seedSampleData()
        let remainingBefore = try months.remainingCents(categoryID: dining.categoryID, month: m)

        let data = try BackupService.export(context: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupService.BackupFile.self, from: data)

        XCTAssertEqual(file.version, 2)
        XCTAssertEqual(file.categories.count, 2)
        XCTAssertEqual(file.transactions.count, 1)
        XCTAssertEqual(file.transfers.count, 1)
        XCTAssertEqual(file.rules.count, 1)
        XCTAssertEqual(file.accounts.count, 1)
        XCTAssertEqual(file.savingGoals?.count, 1)

        // 覆盖导入后数据完整还原
        try BackupService.importReplace(data: data, context: context)

        XCTAssertEqual(try BudgetCategory.all(in: context).count, 2)
        XCTAssertEqual(try Account.all(in: context).count, 1)
        XCTAssertEqual(try SavingGoal.all(in: context).count, 1)
        XCTAssertEqual(try months.monthTransactions(m).count, 1)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), remainingBefore)

        let importedTxn = try XCTUnwrap(try months.monthTransactions(m).first)
        XCTAssertEqual(importedTxn.merchant, "美团外卖")
        XCTAssertEqual(importedTxn.classificationSource, .builtinRule)
        XCTAssertNotNil(importedTxn.categoryID)

        let importedRules = try classification.allRules()
        XCTAssertEqual(importedRules.count, 1)
        XCTAssertEqual(importedRules.first?.keyword, "美团外卖")

        // 转移台账也还原了
        let transfers = try context.fetch(FetchDescriptor<BudgetTransfer>())
        XCTAssertEqual(transfers.count, 1)
        let restoredGoal = try XCTUnwrap(try SavingGoal.all(in: context).first)
        XCTAssertEqual(restoredGoal.name, "旅行基金")
        XCTAssertEqual(restoredGoal.targetCents, Money(yuan: 10_000).cents)
    }

    func testImportReplacesExistingData() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1200)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 1000, description: "麦当劳", categoryID: dining.categoryID, date: date(2026, 8, 5)
        )

        // 导出只含 1 个分区、1 笔交易的备份
        let data = try BackupService.export(context: context)

        // 之后再造新数据
        let fun = try makeCategory(name: "娱乐", monthlyYuan: 500)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 5000, description: "电影", categoryID: fun.categoryID, date: date(2026, 8, 6)
        )
        XCTAssertEqual(try BudgetCategory.all(in: context).count, 2)

        // 导入后回到备份时刻
        try BackupService.importReplace(data: data, context: context)

        XCTAssertEqual(try BudgetCategory.all(in: context).count, 1)
        XCTAssertEqual(try months.monthTransactions(m).count, 1)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 119000)
    }

    func testCorruptFileRejectedWithoutDamagingData() throws {
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1200)
        try months.ensureMonthlyBudget(for: m)

        XCTAssertThrowsError(
            try BackupService.importReplace(data: Data("这不是备份".utf8), context: context)
        )

        // 导入失败不破坏现有数据
        XCTAssertEqual(try BudgetCategory.all(in: context).count, 1)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 120000)
    }

    func testVersionOneBackupWithoutSavingGoalsStillImports() throws {
        _ = try seedSampleData()
        let versionTwoData = try BackupService.export(context: context)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: versionTwoData) as? [String: Any]
        )
        object["version"] = 1
        object.removeValue(forKey: "savingGoals")
        let versionOneData = try JSONSerialization.data(withJSONObject: object)

        try BackupService.importReplace(data: versionOneData, context: context)

        XCTAssertEqual(try BudgetCategory.all(in: context).count, 2)
        XCTAssertEqual(try SavingGoal.all(in: context).count, 0)
    }
}
