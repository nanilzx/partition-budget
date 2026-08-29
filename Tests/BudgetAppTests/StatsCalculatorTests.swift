import XCTest
@testable import BudgetApp

/// 月度统计的纯计算层测试。
final class StatsCalculatorTests: XCTestCase {

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    private func makeTxn(
        _ cents: Int64, day: Int, type: TransactionType = .expense,
        categoryID: UUID? = nil, title: String = "记录"
    ) -> Transaction {
        Transaction(
            type: type, cents: cents,
            date: makeDate(2026, 8, day),
            merchant: title, title: title,
            categoryID: categoryID
        )
    }

    func testDailyExpenseGroupsByDay() {
        let txns = [
            makeTxn(1000, day: 5),
            makeTxn(500, day: 5),
            makeTxn(2000, day: 9),
            makeTxn(650000, day: 1, type: .income), // 收入不计入每日支出
        ]
        let daily = StatsCalculator.dailyExpenseCents(transactions: txns, year: 2026, month: 8)
        XCTAssertEqual(daily[5], 1500)
        XCTAssertEqual(daily[9], 2000)
        XCTAssertNil(daily[1])
    }

    func testTotalsByCategorySortedAndFiltered() {
        let categories = [
            BudgetCategory(name: "餐饮", icon: "fork.knife", colorHex: "#F97316", defaultMonthlyCents: 1000),
            BudgetCategory(name: "娱乐", icon: "gamecontroller", colorHex: "#8B5CF6", defaultMonthlyCents: 500),
        ]
        let diningID = categories[0].categoryID
        let funID = categories[1].categoryID
        let txns = [
            makeTxn(3000, day: 1, categoryID: funID),
            makeTxn(7000, day: 2, categoryID: diningID),
            makeTxn(1000, day: 3, categoryID: UUID()), // 未知分区不计入
        ]
        let totals = StatsCalculator.totalsByCategory(transactions: txns, categories: categories)
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals.first?.name, "餐饮")   // 按金额降序
        XCTAssertEqual(totals.first?.cents, 7000)
        XCTAssertEqual(totals.last?.name, "娱乐")
        XCTAssertEqual(totals.last?.cents, 3000)
    }

    func testDailyAverageAndLargest() {
        let txns = [
            makeTxn(1000, day: 1),
            makeTxn(50000, day: 10, title: "大额"),
            makeTxn(2000, day: 20),
        ]
        XCTAssertEqual(StatsCalculator.expenseCents(transactions: txns), 53000)
        XCTAssertEqual(StatsCalculator.dailyAverageCents(totalExpenseCents: 53000, elapsedDays: 10), 5300)
        XCTAssertEqual(StatsCalculator.dailyAverageCents(totalExpenseCents: 53000, elapsedDays: 0), 0)
        XCTAssertEqual(StatsCalculator.largestExpense(transactions: txns)?.title, "大额")
        XCTAssertEqual(StatsCalculator.incomeCents(transactions: [makeTxn(100, day: 1, type: .income)]), 100)
    }

    func testDaysInMonth() {
        XCTAssertEqual(StatsCalculator.daysInMonth(BudgetMonth(year: 2026, month: 8)), 31)
        XCTAssertEqual(StatsCalculator.daysInMonth(BudgetMonth(year: 2026, month: 2)), 28)
    }
}
