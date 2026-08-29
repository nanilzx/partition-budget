import Foundation
import Observation
import SwiftData

/// 「记一笔」表单的状态机：推荐分类、校验、超支确认的三种落地方式都收在这里。
@MainActor
@Observable
final class AddTransactionModel {
    var isIncome = false
    var amountString = ""
    var merchantText = ""
    var note = ""
    var date = Date()
    var selectedCategoryID: UUID?
    var suggestion: ClassificationResult?
    var showOverBudgetDialog = false
    var showTransferFix = false
    var overBudgetInfo: OverBudgetInfo?

    struct OverBudgetInfo {
        let categoryName: String
        let remainingCents: Int64
        let amountCents: Int64
        let shortfallCents: Int64
    }

    private var editing: Transaction?
    private var userPickedCategory = false

    var amountCents: Int64? {
        guard let cents = Money(string: amountString)?.cents, cents > 0 else { return nil }
        return cents
    }

    var canSave: Bool {
        guard amountCents != nil else { return false }
        return isIncome || selectedCategoryID != nil
    }

    func load(editingTransaction: Transaction?) {
        guard let txn = editingTransaction else { return }
        editing = txn
        isIncome = txn.type == .income
        amountString = Money(cents: txn.cents).inputText
        merchantText = txn.title
        note = txn.note
        date = txn.date
        selectedCategoryID = txn.categoryID
        userPickedCategory = true
    }

    func selectCategory(_ category: BudgetCategory) {
        selectedCategoryID = category.categoryID
        userPickedCategory = true
        suggestion = nil
    }

    /// 根据输入内容推荐分区；用户手动选过之后就不再自动改选。
    func suggestCategory(context: ModelContext) {
        guard !userPickedCategory, !isIncome else { return }
        let categories = (try? BudgetCategory.all(in: context)) ?? []
        let result = ClassificationService(context: context).suggest(text: merchantText, categories: categories)
        suggestion = result
        if let result {
            selectedCategoryID = result.categoryID
        }
    }

    func clearSuggestion() {
        suggestion = nil
    }

    /// 返回 true 表示已弹出超支确认对话框，由 UI 层继续处理五种选择。
    func validate(context: ModelContext) throws -> Bool {
        guard !isIncome, let cents = amountCents, let cid = selectedCategoryID else { return false }
        let months = MonthlyBudgetService(context: context)
        let month = BudgetMonth(date: date)
        guard let category = try BudgetCategory.byID(cid, in: context) else { return false }
        _ = try months.ensureItem(categoryID: cid, month: month)
        guard let item = try months.item(categoryID: cid, month: month) else { return false }

        let spentWithoutThis = try months.spentCents(
            categoryID: cid, month: month, excluding: editing?.transactionID
        )
        let remaining = item.adjustedCents - spentWithoutThis
        // 已经超支的分区不再重复提醒，避免打断正常编辑
        guard remaining >= 0 else { return false }
        let shortfall = cents - remaining
        guard shortfall > 0 else { return false }

        overBudgetInfo = OverBudgetInfo(
            categoryName: category.name,
            remainingCents: remaining,
            amountCents: cents,
            shortfallCents: shortfall
        )
        showOverBudgetDialog = true
        return true
    }

    /// 常规保存（新增/编辑都走这里）。
    func save(context: ModelContext) throws {
        guard let cents = amountCents else { throw ServiceError.invalidAmount }
        let service = TransactionService(context: context)
        let description = merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let txn = editing {
            try service.update(
                txn,
                cents: cents,
                description: description,
                note: note,
                categoryID: isIncome ? nil : selectedCategoryID,
                date: date
            )
        } else if isIncome {
            try service.addIncome(
                cents: cents,
                description: description.isEmpty ? "收入" : description,
                note: note,
                date: date
            )
        } else if let cid = selectedCategoryID {
            try service.addExpense(
                cents: cents,
                description: description.isEmpty ? "消费" : description,
                note: note,
                categoryID: cid,
                date: date,
                classificationSource: suggestion?.source ?? .manual,
                confidence: suggestion?.confidence ?? 1.0
            )
        }
    }

    /// 超支时的「增加本月预算」：补上差额后正常保存。
    func saveWithBudgetBoost(context: ModelContext) throws {
        guard let info = overBudgetInfo, let cid = selectedCategoryID else { return }
        try BudgetService(context: context).adjustBudget(
            categoryID: cid,
            month: BudgetMonth(date: date),
            deltaCents: info.shortfallCents,
            reason: "超支补充——\(merchantText)"
        )
        try save(context: context)
    }
}
