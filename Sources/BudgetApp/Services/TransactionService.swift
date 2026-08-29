import Foundation
import SwiftData

/// 消费/收入记录的业务规则（规格第二十九节：核心逻辑不放 UI 层）。
/// 预算余额一律由交易派生，因此这里只负责「写入正确的事实」，不做余额加减。
struct TransactionService {
    let context: ModelContext

    private var months: MonthlyBudgetService { MonthlyBudgetService(context: context) }

    /// 记一笔支出：自动绑定到消费日期所在月的分区预算项。
    @discardableResult
    func addExpense(
        cents: Int64,
        description: String,
        note: String = "",
        categoryID: UUID,
        date: Date = Date(),
        classificationSource: ClassificationSource = .manual,
        confidence: Double = 1.0
    ) throws -> Transaction {
        guard cents > 0 else { throw ServiceError.invalidAmount }
        let month = BudgetMonth(date: date)
        _ = try months.ensureItem(categoryID: categoryID, month: month)

        let transaction = Transaction(
            type: .expense,
            cents: cents,
            date: date,
            merchant: description,
            title: description,
            note: note,
            categoryID: categoryID,
            classificationSource: classificationSource,
            confidence: confidence
        )
        context.insert(transaction)
        try context.save()
        return transaction
    }

    /// 记一笔收入（不参与预算扣减，只影响本月收入与未分配）。
    @discardableResult
    func addIncome(
        cents: Int64,
        description: String,
        note: String = "",
        date: Date = Date()
    ) throws -> Transaction {
        guard cents > 0 else { throw ServiceError.invalidAmount }
        let transaction = Transaction(
            type: .income,
            cents: cents,
            date: date,
            merchant: description,
            title: description,
            note: note,
            categoryID: nil
        )
        context.insert(transaction)
        try context.save()
        return transaction
    }

    /// 编辑记录。金额差值、分区变更、跨月改日期都通过派生计算自动反映到对应预算：
    /// - 改金额：该分区余额按差值自动变化
    /// - 改分区：原分区自动恢复，新分区自动扣除
    /// - 改日期跨月：旧月恢复、新月扣除
    func update(
        _ transaction: Transaction,
        cents: Int64? = nil,
        description: String? = nil,
        note: String? = nil,
        categoryID: UUID? = nil,
        date: Date? = nil
    ) throws {
        if let cents {
            guard cents > 0 else { throw ServiceError.invalidAmount }
        }

        let newCents = cents ?? transaction.cents
        let newDescription = description ?? transaction.merchant
        let newNote = note ?? transaction.note
        let newDate = date ?? transaction.date
        let newCategoryID = categoryID ?? transaction.categoryID

        let newMonth = BudgetMonth(date: newDate)
        if transaction.type == .expense, let target = newCategoryID {
            _ = try months.ensureItem(categoryID: target, month: newMonth)
        }

        transaction.cents = newCents
        transaction.merchant = newDescription
        transaction.title = newDescription
        transaction.note = newNote
        transaction.date = newDate
        transaction.year = newMonth.year
        transaction.month = newMonth.month
        transaction.categoryID = newCategoryID

        if cents != nil || description != nil || note != nil || categoryID != nil || date != nil {
            transaction.isUserCorrected = true
            transaction.updatedAt = Date()
        }
        if categoryID != nil {
            // 用户纠正了分类：来源改回手动，让历史匹配层学到这条新规则
            transaction.classificationSource = .manual
            transaction.confidence = 1.0
        }
        try context.save()
    }

    /// 删除记录。支出删除后，对应分区余额通过派生计算自动恢复。
    func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }
}
