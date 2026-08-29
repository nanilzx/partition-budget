import Foundation
import SwiftData

/// 月度预算生命周期：惰性创建、月度重置、余额结转，以及从交易派生的各项金额。
/// 月度创建是幂等的：同一月只会创建一次，已存在则直接返回。
struct MonthlyBudgetService {
    let context: ModelContext

    // MARK: - 查询

    func monthlyBudget(for month: BudgetMonth) throws -> MonthlyBudget? {
        let year = month.year
        let monthNumber = month.month
        var descriptor = FetchDescriptor<MonthlyBudget>(
            predicate: #Predicate { $0.year == year && $0.month == monthNumber }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func items(in month: BudgetMonth) throws -> [MonthlyBudgetItem] {
        let year = month.year
        let monthNumber = month.month
        return try context.fetch(
            FetchDescriptor<MonthlyBudgetItem>(
                predicate: #Predicate { $0.year == year && $0.month == monthNumber },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    func item(categoryID: UUID, month: BudgetMonth) throws -> MonthlyBudgetItem? {
        let year = month.year
        let monthNumber = month.month
        let category = categoryID
        var descriptor = FetchDescriptor<MonthlyBudgetItem>(
            predicate: #Predicate {
                $0.year == year && $0.month == monthNumber && $0.categoryID == category
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func monthTransactions(_ month: BudgetMonth) throws -> [Transaction] {
        let year = month.year
        let monthNumber = month.month
        return try context.fetch(
            FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.year == year && $0.month == monthNumber },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    // MARK: - 派生金额

    /// 某月某分区的已花金额 = 当月该分区全部支出交易之和。
    /// 这是全 App 唯一的「已花」算法；`excluding` 用于编辑时先刨除旧值再预估。
    func spentCents(categoryID: UUID, month: BudgetMonth, excluding transactionID: UUID? = nil) throws -> Int64 {
        try monthTransactions(month)
            .filter {
                $0.type == .expense
                    && $0.categoryID == categoryID
                    && $0.transactionID != transactionID
            }
            .reduce(Int64(0)) { $0 + $1.cents }
    }

    /// 剩余 = 该月该项的可用总额 − 已花。可以为负（超支是允许的）。
    func remainingCents(categoryID: UUID, month: BudgetMonth) throws -> Int64 {
        guard let item = try item(categoryID: categoryID, month: month) else { return 0 }
        let spent = try spentCents(categoryID: categoryID, month: month)
        return item.adjustedCents - spent
    }

    func incomeCents(month: BudgetMonth) throws -> Int64 {
        try monthTransactions(month)
            .filter { $0.type == .income }
            .reduce(Int64(0)) { $0 + $1.cents }
    }

    // MARK: - 创建与结转

    /// 确保某月的月度预算存在。打开 App 或进入新月时调用即可完成「月度重置」：
    /// 非隐藏分区按默认金额生成；开启结转的分区额外加上月剩余（负数不结转）。
    @discardableResult
    func ensureMonthlyBudget(for month: BudgetMonth) throws -> MonthlyBudget {
        if let existing = try monthlyBudget(for: month) { return existing }

        let budget = MonthlyBudget(year: month.year, month: month.month)
        context.insert(budget)

        let categories = try BudgetCategory.all(in: context)
        for category in categories where !category.isHidden {
            try createItemIfNeeded(for: category, budget: budget, month: month)
        }
        try context.save()
        return budget
    }

    /// 确保某月某分区的预算项存在（月中新建分区、给历史月份补记录时惰性创建）。
    @discardableResult
    func ensureItem(categoryID: UUID, month: BudgetMonth) throws -> MonthlyBudgetItem {
        if let existing = try item(categoryID: categoryID, month: month) { return existing }
        guard let category = try BudgetCategory.byID(categoryID, in: context) else {
            throw ServiceError.categoryNotFound
        }
        let budget = try ensureMonthlyBudget(for: month)
        let item = try createItemIfNeeded(for: category, budget: budget, month: month)
        try context.save()
        return item
    }

    @discardableResult
    private func createItemIfNeeded(
        for category: BudgetCategory,
        budget: MonthlyBudget,
        month: BudgetMonth
    ) throws -> MonthlyBudgetItem {
        if let existing = try item(categoryID: category.categoryID, month: month) { return existing }

        var carryOver: Int64 = 0
        if category.carryOverEnabled {
            let previous = month.previous
            if let previousItem = try item(categoryID: category.categoryID, month: previous) {
                let previousSpent = try spentCents(categoryID: category.categoryID, month: previous)
                // 超支的负数不结转到下个月
                carryOver = max(0, previousItem.adjustedCents - previousSpent)
            }
        }

        let item = MonthlyBudgetItem(
            monthlyBudgetID: budget.monthlyBudgetID,
            year: month.year,
            month: month.month,
            categoryID: category.categoryID,
            initialCents: category.defaultMonthlyCents,
            carryOverCents: carryOver
        )
        context.insert(item)
        budget.allocatedCents += category.defaultMonthlyCents

        if category.defaultMonthlyCents != 0 {
            context.insert(
                BudgetAdjustment(
                    categoryID: category.categoryID,
                    year: month.year,
                    month: month.month,
                    cents: category.defaultMonthlyCents,
                    type: .initial,
                    reason: "本月预算初始化",
                    date: Date()
                )
            )
        }
        if carryOver > 0 {
            context.insert(
                BudgetAdjustment(
                    categoryID: category.categoryID,
                    year: month.year,
                    month: month.month,
                    cents: carryOver,
                    type: .carryOver,
                    reason: "上月余额结转",
                    date: Date()
                )
            )
        }
        return item
    }
}
