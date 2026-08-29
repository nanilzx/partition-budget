import XCTest
@testable import BudgetApp

/// 智能分类优先级（规格第五、六节）：历史记录 > 内置词库；用户纠正自动生效。
final class ClassificationTests: ServiceTestCase {

    func testBuiltinRuleSuggestsCategory() throws {
        let dining = try makeCategory(name: "餐饮")

        let result = ClassificationService(context: context)
            .suggest(text: "麦当劳午饭", categories: [dining])

        XCTAssertEqual(result?.categoryID, dining.categoryID)
        XCTAssertEqual(result?.source, .builtinRule)
        XCTAssertFalse(result?.isLowConfidence ?? true)
    }

    // 内置词库只在存在同名分区时生效
    func testBuiltinRuleNeedsSameNameCategory() throws {
        let fun = try makeCategory(name: "娱乐")

        let result = ClassificationService(context: context)
            .suggest(text: "麦当劳", categories: [fun])

        XCTAssertNil(result)
    }

    // 最长关键词优先：「地铁站便利店」应命中「便利店」(购物) 而不是「地铁」(交通)
    func testLongestKeywordWins() throws {
        let traffic = try makeCategory(name: "交通")
        let shopping = try makeCategory(name: "购物")

        let result = ClassificationService(context: context)
            .suggest(text: "地铁站便利店", categories: [traffic, shopping])

        XCTAssertEqual(result?.categoryID, shopping.categoryID)
    }

    // 历史优先级高于内置词库
    func testHistoryBeatsBuiltinRules() throws {
        let dining = try makeCategory(name: "餐饮")
        let fun = try makeCategory(name: "娱乐")
        // 用户把「京东」记到了娱乐（比如买游戏），历史应优先于词库的「京东→购物」
        try transactions.addExpense(
            cents: 20000, description: "京东",
            categoryID: fun.categoryID, date: date(2026, 8, 1)
        )

        let result = ClassificationService(context: context)
            .suggest(text: "京东买书", categories: [dining, fun])

        XCTAssertEqual(result?.source, .historyRule)
        XCTAssertEqual(result?.categoryID, fun.categoryID)
    }

    // 规格第六节：Steam 从购物纠正到娱乐后，"STEAM PURCHASE" 也应推荐娱乐
    func testUserCorrectionLearnsAcrossVariants() throws {
        let shopping = try makeCategory(name: "购物")
        let fun = try makeCategory(name: "娱乐")
        let txn = try transactions.addExpense(
            cents: 9800, description: "Steam",
            categoryID: shopping.categoryID, date: date(2026, 8, 1)
        )

        try transactions.update(txn, categoryID: fun.categoryID)

        XCTAssertTrue(txn.isUserCorrected)
        let result = ClassificationService(context: context)
            .suggest(text: "STEAM PURCHASE", categories: [shopping, fun])
        XCTAssertEqual(result?.source, .historyRule)
        XCTAssertEqual(result?.categoryID, fun.categoryID)
    }

    func testUnknownTextReturnsNil() throws {
        let dining = try makeCategory(name: "餐饮")

        let result = ClassificationService(context: context)
            .suggest(text: "某某 unidentified 事务", categories: [dining])

        XCTAssertNil(result)
    }

    func testEmptyTextReturnsNil() {
        let dining = try? makeCategory(name: "餐饮")
        XCTAssertNotNil(dining)
        let result = ClassificationService(context: context).suggest(text: "  ", categories: [dining!])
        XCTAssertNil(result)
    }
}
