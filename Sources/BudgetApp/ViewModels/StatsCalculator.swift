import Foundation

/// 月度统计的纯计算层（规格第十九节：只做简单统计）。
/// 输入模型数组，输出可展示的数据，便于单元测试。
enum StatsCalculator {

    // MARK: - 每日支出（柱状图数据）

    static func dailyExpenseCents(
        transactions: [Transaction],
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> [Int: Int64] {
        var result: [Int: Int64] = [:]
        for txn in transactions where txn.type == .expense {
            let day = calendar.component(.day, from: txn.date)
            result[day, default: 0] += txn.cents
        }
        return result
    }

    static func daysInMonth(_ month: BudgetMonth, calendar: Calendar = .current) -> Int {
        var comps = DateComponents()
        comps.year = month.year
        comps.month = month.month
        guard let start = calendar.date(from: comps),
              let interval = calendar.dateInterval(of: .day, for: start) else {
            return 30
        }
        return calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
    }

    // MARK: - 分区消费排行

    struct CategoryTotal: Identifiable, Equatable {
        let categoryID: UUID
        let name: String
        let colorHex: String
        let cents: Int64
        var id: UUID { categoryID }
    }

    static func totalsByCategory(
        transactions: [Transaction],
        categories: [BudgetCategory]
    ) -> [CategoryTotal] {
        categories.map { category in
            let cents = transactions
                .filter { $0.type == .expense && $0.categoryID == category.categoryID }
                .reduce(Int64(0)) { $0 + $1.cents }
            return CategoryTotal(
                categoryID: category.categoryID,
                name: category.name,
                colorHex: category.colorHex,
                cents: cents
            )
        }
        .filter { $0.cents > 0 }
        .sorted { $0.cents > $1.cents }
    }

    // MARK: - 概览数字

    static func expenseCents(transactions: [Transaction]) -> Int64 {
        transactions.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.cents }
    }

    static func incomeCents(transactions: [Transaction]) -> Int64 {
        transactions.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.cents }
    }

    /// 日均支出：按当月已经过的天数计算（未来天数不计入）。
    static func dailyAverageCents(totalExpenseCents: Int64, elapsedDays: Int) -> Int64 {
        guard elapsedDays > 0 else { return 0 }
        return totalExpenseCents / Int64(elapsedDays)
    }

    static func largestExpense(transactions: [Transaction]) -> Transaction? {
        transactions
            .filter { $0.type == .expense }
            .max { $0.cents < $1.cents }
    }
}
