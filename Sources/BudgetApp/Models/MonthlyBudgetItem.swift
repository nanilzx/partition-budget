import Foundation
import SwiftData

/// 某个月、某个分区的预算项（规格第二十七节 MonthlyBudgetItem）。
/// adjustedCents 是当前可用总额 = 初始分配 + 手动调整 + 转移净额 + 上月结转。
/// 「已花」不在此存储：由当月该分区的全部支出交易求和派生（单一事实来源，
/// 见 MonthlyBudgetService.spentCents），因此新增/修改/删除消费后余额不可能漂移。
@Model
final class MonthlyBudgetItem {
    var itemID: UUID = UUID()
    var monthlyBudgetID: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var categoryID: UUID = UUID()
    var initialCents: Int64 = 0
    var adjustedCents: Int64 = 0
    var carryOverCents: Int64 = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var monthKey: BudgetMonth { BudgetMonth(year: year, month: month) }

    init(
        monthlyBudgetID: UUID,
        year: Int,
        month: Int,
        categoryID: UUID,
        initialCents: Int64,
        carryOverCents: Int64 = 0
    ) {
        self.itemID = UUID()
        self.monthlyBudgetID = monthlyBudgetID
        self.year = year
        self.month = month
        self.categoryID = categoryID
        self.initialCents = initialCents
        self.carryOverCents = carryOverCents
        self.adjustedCents = initialCents + carryOverCents
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
