import Foundation

/// 预算月（年 + 月）。所有月度数据（月度预算、消费归属）都以它为键，保证不同月份数据隔离。
struct BudgetMonth: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
    }

    static var current: BudgetMonth { BudgetMonth(date: Date()) }

    var previous: BudgetMonth {
        month == 1 ? BudgetMonth(year: year - 1, month: 12) : BudgetMonth(year: year, month: month - 1)
    }

    var next: BudgetMonth {
        month == 12 ? BudgetMonth(year: year + 1, month: 1) : BudgetMonth(year: year, month: month + 1)
    }

    var title: String { "\(year)年\(month)月" }

    static func < (lhs: BudgetMonth, rhs: BudgetMonth) -> Bool {
        lhs.year != rhs.year ? lhs.year < rhs.year : lhs.month < rhs.month
    }
}
