import Foundation
import SwiftData

/// 消费/收入记录的业务规则（规格第二十九节：核心逻辑不放 UI 层）。
/// 预算余额一律由交易派生，因此这里只负责「写入正确的事实」，不做余额加减。
struct TransactionService {
    let context: ModelContext

    private var months: MonthlyBudgetService { MonthlyBudgetService(context: context) }

    /// 记一笔支出：自动绑定到消费日期所在月的分区预算项；可选绑定资金账户。
    @discardableResult
    func addExpense(
        cents: Int64,
        description: String,
        note: String = "",
        categoryID: UUID,
        date: Date = Date(),
        accountID: UUID? = nil,
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
            accountID: accountID,
            classificationSource: classificationSource,
            confidence: confidence
        )
        context.insert(transaction)
        try context.save()
        return transaction
    }

    /// 记一笔收入（不参与预算扣减，只影响本月收入与未分配）；可选绑定资金账户。
    @discardableResult
    func addIncome(
        cents: Int64,
        description: String,
        note: String = "",
        date: Date = Date(),
        accountID: UUID? = nil
    ) throws -> Transaction {
        guard cents > 0 else { throw ServiceError.invalidAmount }
        let transaction = Transaction(
            type: .income,
            cents: cents,
            date: date,
            merchant: description,
            title: description,
            note: note,
            categoryID: nil,
            accountID: accountID
        )
        context.insert(transaction)
        try context.save()
        return transaction
    }

    /// 编辑记录。金额差值、分区变更、跨月改日期都通过派生计算自动反映到对应预算：
    /// - 改金额：该分区余额按差值自动变化
    /// - 改分区：原分区自动恢复，新分区自动扣除，并生成用户自定义规则
    /// - 改日期跨月：旧月恢复、新月扣除
    /// - accountID 传 nil 表示不修改，传 .some(x) 表示改为绑定 x（再传 .some(nil) 解绑）
    func update(
        _ transaction: Transaction,
        cents: Int64? = nil,
        description: String? = nil,
        note: String? = nil,
        categoryID: UUID? = nil,
        accountID: UUID?? = nil,
        date: Date? = nil
    ) throws {
        if let cents {
            guard cents > 0 else { throw ServiceError.invalidAmount }
        }

        let oldCategoryID = transaction.categoryID
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
        if let newAccount = accountID {
            transaction.accountID = newAccount
        }

        if cents != nil || description != nil || note != nil || categoryID != nil || accountID != nil || date != nil {
            transaction.isUserCorrected = true
            transaction.updatedAt = Date()
        }
        if categoryID != nil {
            // 用户纠正了分类：来源改回手动，让推荐层学到这条新规则
            transaction.classificationSource = .manual
            transaction.confidence = 1.0
        }

        // 规格第六节：纠正分类后生成/覆盖用户自定义规则，下次同样内容直接命中
        if let target = newCategoryID, target != oldCategoryID, transaction.type == .expense {
            let keyword = transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if keyword.count >= 2 {
                try? ClassificationService(context: context).upsertRule(
                    keyword: keyword,
                    categoryID: target
                )
            }
        }
        try context.save()
    }

    /// 删除记录。支出删除后，对应分区余额通过派生计算自动恢复。
    func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }
}
