import Foundation
import SwiftData

/// 月度预算（规格第二十七节 MonthlyBudget）：每个 (year, month) 一条。
/// allocatedCents = 本月已分配总额（初始分配 + 手动调整；转移不改总额、结转不算新分配）。
/// 本月收入不在此存储，由当月收入类交易求和派生。
@Model
final class MonthlyBudget {
    var monthlyBudgetID: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var allocatedCents: Int64 = 0
    var createdAt: Date = Date()

    var monthKey: BudgetMonth { BudgetMonth(year: year, month: month) }

    init(year: Int, month: Int) {
        self.monthlyBudgetID = UUID()
        self.year = year
        self.month = month
        self.allocatedCents = 0
        self.createdAt = Date()
    }
}
