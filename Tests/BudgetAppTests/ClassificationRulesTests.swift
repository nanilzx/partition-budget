import XCTest
import SwiftData
@testable import BudgetApp

/// 用户自定义分类规则：最高优先级、自动学习（规格第六节）。
final class ClassificationRulesTests: ServiceTestCase {

    // 规则优先级高于历史记录与内置词库
    func testUserRuleBeatsHistoryAndBuiltin() throws {
        let dining = try makeCategory(name: "餐饮")
        let fun = try makeCategory(name: "娱乐")
        // 历史里「京东」记到过娱乐，内置词库说「京东」是购物；用户规则定成餐饮
        try transactions.addExpense(
            cents: 1000, description: "京东", categoryID: fun.categoryID, date: date(2026, 8, 1)
        )
        try classification.upsertRule(keyword: "京东", categoryID: dining.categoryID)

        let result = classification.suggest(text: "京东买书", categories: [dining, fun])

        XCTAssertEqual(result?.source, .userRule)
        XCTAssertEqual(result?.categoryID, dining.categoryID)
    }

    // 同关键词重复添加 = 覆盖
    func testUpsertOverwritesSameKeyword() throws {
        let dining = try makeCategory(name: "餐饮")
        let fun = try makeCategory(name: "娱乐")

        try classification.upsertRule(keyword: "瑞幸", categoryID: fun.categoryID)
        try classification.upsertRule(keyword: "瑞幸", categoryID: dining.categoryID)

        let rules = try classification.allRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.categoryID, dining.categoryID)
    }

    // 规格第六节：系统推荐错误 → 用户纠正 → 以后自动命中纠正后的分区
    func testCorrectionGeneratesRuleAndLearns() throws {
        let shopping = try makeCategory(name: "购物")
        let fun = try makeCategory(name: "娱乐")
        let txn = try transactions.addExpense(
            cents: 9800, description: "Steam", categoryID: shopping.categoryID, date: date(2026, 8, 1)
        )

        // 用户手动纠正到娱乐（update 内部自动生成规则）
        try transactions.update(txn, categoryID: fun.categoryID)

        let rules = try classification.allRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.keyword, "steam")
        XCTAssertEqual(rules.first?.categoryID, fun.categoryID)

        let result = classification.suggest(text: "STEAM PURCHASE", categories: [shopping, fun])
        XCTAssertEqual(result?.source, .userRule)
        XCTAssertEqual(result?.categoryID, fun.categoryID)
    }

    func testShortKeywordRejected() throws {
        let dining = try makeCategory(name: "餐饮")
        let rule = try classification.upsertRule(keyword: "麦", categoryID: dining.categoryID)
        XCTAssertNil(rule)
        XCTAssertTrue(try classification.allRules().isEmpty)
    }

    func testDeleteRule() throws {
        let dining = try makeCategory(name: "餐饮")
        let rule = try XCTUnwrap(try classification.upsertRule(keyword: "麦当劳", categoryID: dining.categoryID))

        try classification.deleteRule(rule)

        XCTAssertTrue(try classification.allRules().isEmpty)
    }
}
