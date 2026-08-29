import XCTest
import SwiftData
@testable import BudgetApp

/// 储蓄目标：CRUD 与校验（规格第十七节）。
final class SavingGoalServiceTests: ServiceTestCase {

    private func makeSavingCategory() throws -> BudgetCategory {
        try makeCategory(name: "储蓄", monthlyYuan: 1000, carryOver: true, saving: true)
    }

    func testCreateUpdateDeleteGoal() throws {
        let saving = try makeSavingCategory()
        let service = SavingGoalService(context: context)

        let goal = try service.create(
            name: "电脑基金",
            categoryID: saving.categoryID,
            targetCents: Money(yuan: 8000).cents,
            targetDate: date(2026, 12, 31)
        )
        XCTAssertEqual(try SavingGoal.all(in: context).count, 1)
        XCTAssertEqual(goal.name, "电脑基金")

        try service.update(goal, name: "旅行基金", targetCents: Money(yuan: 12000).cents)
        XCTAssertEqual(try SavingGoal.all(in: context).first?.name, "旅行基金")
        XCTAssertEqual(try SavingGoal.all(in: context).first?.targetCents, 1200000)

        try service.delete(goal)
        XCTAssertTrue(try SavingGoal.all(in: context).isEmpty)
    }

    func testInvalidGoalRejected() throws {
        let saving = try makeSavingCategory()
        let service = SavingGoalService(context: context)

        XCTAssertThrowsError(try service.create(name: "", categoryID: saving.categoryID, targetCents: 1000, targetDate: nil))
        XCTAssertThrowsError(try service.create(name: "电脑基金", categoryID: saving.categoryID, targetCents: 0, targetDate: nil))
        XCTAssertTrue(try SavingGoal.all(in: context).isEmpty)
    }
}
