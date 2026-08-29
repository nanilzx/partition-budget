import Foundation
import SwiftData

/// 分区管理、预算调整、预算转移（规格第二/八/九/十八节）。
struct BudgetService {
    let context: ModelContext

    private var months: MonthlyBudgetService { MonthlyBudgetService(context: context) }

    // MARK: - 分区管理

    @discardableResult
    func createCategory(
        name: String,
        icon: String,
        colorHex: String,
        defaultMonthlyCents: Int64,
        carryOverEnabled: Bool,
        isSavingCategory: Bool
    ) throws -> BudgetCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServiceError.invalidName }
        let all = try BudgetCategory.all(in: context)
        guard !all.contains { $0.name == trimmed } else {
            throw ServiceError.duplicateName(trimmed)
        }
        let category = BudgetCategory(
            name: trimmed,
            icon: icon,
            colorHex: colorHex,
            defaultMonthlyCents: defaultMonthlyCents,
            carryOverEnabled: carryOverEnabled,
            isSavingCategory: isSavingCategory,
            sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(category)
        try context.save()
        return category
    }

    func updateCategory(
        _ category: BudgetCategory,
        name: String? = nil,
        icon: String? = nil,
        colorHex: String? = nil,
        defaultMonthlyCents: Int64? = nil,
        carryOverEnabled: Bool? = nil,
        isSavingCategory: Bool? = nil
    ) throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ServiceError.invalidName }
            let clash = try BudgetCategory.all(in: context).contains {
                $0.name == trimmed && $0.categoryID != category.categoryID
            }
            guard !clash else { throw ServiceError.duplicateName(trimmed) }
            category.name = trimmed
        }
        if let icon { category.icon = icon }
        if let colorHex { category.colorHex = colorHex }
        if let defaultMonthlyCents { category.defaultMonthlyCents = defaultMonthlyCents }
        if let carryOverEnabled { category.carryOverEnabled = carryOverEnabled }
        if let isSavingCategory { category.isSavingCategory = isSavingCategory }
        category.updatedAt = Date()
        try context.save()
    }

    /// 删除分区（规格第二节：有关联消费记录时必须阻止，避免历史记录失效）。
    func deleteCategory(_ category: BudgetCategory) throws {
        let count = try transactionCount(categoryID: category.categoryID)
        guard count == 0 else { throw ServiceError.categoryInUse(count) }

        // 无消费记录：连同各月预算项、转移与台账一起移除，避免悬挂引用。
        // 其他分区因转移获得的额度保持不变。
        let cid = category.categoryID
        let items = try context.fetch(
            FetchDescriptor<MonthlyBudgetItem>(predicate: #Predicate { $0.categoryID == cid })
        )
        for item in items {
            if let budget = try months.monthlyBudget(for: item.monthKey) {
                // 从月度已分配总额中扣掉该分区的贡献（结转部分不算分配）
                budget.allocatedCents -= (item.adjustedCents - item.carryOverCents)
            }
            context.delete(item)
        }
        let transfers = try context.fetch(
            FetchDescriptor<BudgetTransfer>(
                predicate: #Predicate { $0.fromCategoryID == cid || $0.toCategoryID == cid }
            )
        )
        transfers.forEach(context.delete)
        let adjustments = try context.fetch(
            FetchDescriptor<BudgetAdjustment>(predicate: #Predicate { $0.categoryID == cid })
        )
        adjustments.forEach(context.delete)
        context.delete(category)
        try context.save()
    }

    func setCategoryHidden(_ category: BudgetCategory, hidden: Bool) throws {
        category.isHidden = hidden
        category.updatedAt = Date()
        try context.save()
    }

    /// 拖拽排序后写回 sortOrder。
    func reorder(_ orderedCategories: [BudgetCategory]) throws {
        for (index, category) in orderedCategories.enumerated() where category.sortOrder != index {
            category.sortOrder = index
            category.updatedAt = Date()
        }
        try context.save()
    }

    private func transactionCount(categoryID: UUID) throws -> Int {
        try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.categoryID == categoryID }
            .count
    }

    // MARK: - 预算调整与转移

    /// 手动增减某月某分区的预算（如超支时的「增加本月预算」），deltaCents 可为负。
    func adjustBudget(categoryID: UUID, month: BudgetMonth, deltaCents: Int64, reason: String) throws {
        guard deltaCents != 0 else { return }
        let budget = try months.ensureMonthlyBudget(for: month)
        let item = try months.ensureItem(categoryID: categoryID, month: month)
        item.adjustedCents += deltaCents
        budget.allocatedCents += deltaCents
        context.insert(
            BudgetAdjustment(
                categoryID: categoryID,
                year: month.year,
                month: month.month,
                cents: deltaCents,
                type: .manual,
                reason: reason
            )
        )
        try context.save()
    }

    /// 「分配预算」页：设置某月某分区的初始分配额，差额记入手动调整台账。
    func setInitialAllocation(categoryID: UUID, month: BudgetMonth, cents: Int64) throws {
        guard cents >= 0 else { throw ServiceError.invalidAmount }
        let budget = try months.ensureMonthlyBudget(for: month)
        let item = try months.ensureItem(categoryID: categoryID, month: month)
        let delta = cents - item.initialCents
        guard delta != 0 else { return }
        item.initialCents = cents
        item.adjustedCents += delta
        budget.allocatedCents += delta
        context.insert(
            BudgetAdjustment(
                categoryID: categoryID,
                year: month.year,
                month: month.month,
                cents: delta,
                type: .manual,
                reason: "月度预算分配调整"
            )
        )
        try context.save()
    }

    /// 预算转移：把来源分区当月的剩余额度转给目标分区（不能超过来源剩余）。
    func transfer(
        fromCategoryID: UUID,
        toCategoryID: UUID,
        cents: Int64,
        month: BudgetMonth,
        note: String = ""
    ) throws {
        guard fromCategoryID != toCategoryID else { throw ServiceError.transferSameCategory }
        guard cents > 0 else { throw ServiceError.invalidAmount }

        let from = try months.ensureItem(categoryID: fromCategoryID, month: month)
        let to = try months.ensureItem(categoryID: toCategoryID, month: month)
        let fromSpent = try months.spentCents(categoryID: fromCategoryID, month: month)
        guard cents <= from.adjustedCents - fromSpent else {
            throw ServiceError.transferExceedsRemaining
        }

        let transfer = BudgetTransfer(
            fromCategoryID: fromCategoryID,
            toCategoryID: toCategoryID,
            cents: cents,
            date: Date(),
            note: note
        )
        from.adjustedCents -= cents
        to.adjustedCents += cents
        context.insert(transfer)

        let fromName = try BudgetCategory.byID(fromCategoryID, in: context)?.name ?? "—"
        let toName = try BudgetCategory.byID(toCategoryID, in: context)?.name ?? "—"
        context.insert(
            BudgetAdjustment(
                categoryID: fromCategoryID,
                year: month.year,
                month: month.month,
                cents: -cents,
                type: .transferOut,
                reason: "转移至「\(toName)」",
                relatedID: transfer.transferID
            )
        )
        context.insert(
            BudgetAdjustment(
                categoryID: toCategoryID,
                year: month.year,
                month: month.month,
                cents: cents,
                type: .transferIn,
                reason: "来自「\(fromName)」",
                relatedID: transfer.transferID
            )
        )
        try context.save()
    }
}
