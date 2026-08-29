import Foundation
import SwiftData

/// 预算转移记录（规格第二十七节 BudgetTransfer）。
/// 只是把某月额度在分区之间重新分配，不是银行卡转账。
@Model
final class BudgetTransfer {
    var transferID: UUID = UUID()
    var fromCategoryID: UUID = UUID()
    var toCategoryID: UUID = UUID()
    var cents: Int64 = 0
    var date: Date = Date()
    var year: Int = 0
    var month: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    init(
        fromCategoryID: UUID,
        toCategoryID: UUID,
        cents: Int64,
        date: Date,
        note: String = ""
    ) {
        self.transferID = UUID()
        self.fromCategoryID = fromCategoryID
        self.toCategoryID = toCategoryID
        self.cents = cents
        self.date = date
        let budgetMonth = BudgetMonth(date: date)
        self.year = budgetMonth.year
        self.month = budgetMonth.month
        self.note = note
        self.createdAt = Date()
    }
}
