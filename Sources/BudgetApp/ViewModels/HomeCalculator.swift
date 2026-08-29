import Foundation
import Observation
import SwiftData

/// 首页顶部的汇总数据（单位：分）。
struct HomeSummary {
    let totalBudgetCents: Int64     // 日常（非储蓄）分区可用总额
    let spentCents: Int64           // 日常分区已花
    let incomeCents: Int64          // 本月收入
    let allocatedCents: Int64       // 本月已分配（含储蓄）

    var remainingCents: Int64 { totalBudgetCents - spentCents }
    var unallocatedCents: Int64 { incomeCents - allocatedCents }
}

/// 预算卡片的展示状态（规格第十四节：正常 / 提醒 / 警告 / 超支，语气平和）。
enum BudgetStatus {
    case normal
    case notice
    case warning
    case overspent
    case unallocated

    var caption: String {
        switch self {
        case .normal: return "剩余充足"
        case .notice: return "剩余不多"
        case .warning: return "即将用完"
        case .overspent: return "已超支"
        case .unallocated: return "未分配本月预算"
        }
    }
}

/// 首页预算分区卡片的数据。
struct CategoryCardModel: Identifiable {
    let categoryID: UUID
    let name: String
    let icon: String
    let colorHex: String
    let budgetCents: Int64
    let spentCents: Int64
    let remainingCents: Int64
    let usageRatio: Double
    let status: BudgetStatus

    var id: UUID { categoryID }

    var percentText: String {
        "\(Int((usageRatio * 100).rounded()))%"
    }
}

/// 首页数据的纯计算层：输入模型数组，输出汇总与卡片，方便单测与复用。
enum HomeCalculator {
    static func status(remainingCents: Int64, adjustedCents: Int64) -> BudgetStatus {
        guard adjustedCents > 0 else { return .unallocated }
        if remainingCents < 0 { return .overspent }
        let ratio = Double(remainingCents) / Double(adjustedCents)
        // 规格第十四节：剩余 30% 提醒、剩余 10% 警告（恰好落在阈值上按更醒目的一档处理）
        if ratio > 0.3 { return .normal }
        if ratio > 0.1 { return .notice }
        return .warning
    }

    static func summarize(
        categories: [BudgetCategory],
        items: [MonthlyBudgetItem],
        monthlyBudget: MonthlyBudget?,
        transactions: [Transaction]
    ) -> HomeSummary {
        let dailyIDs = Set(categories.filter { !$0.isSavingCategory }.map(\.categoryID))
        let totalBudget = items
            .filter { dailyIDs.contains($0.categoryID) }
            .reduce(Int64(0)) { $0 + $1.adjustedCents }
        let spent = transactions
            .filter { $0.type == .expense && ($0.categoryID.map(dailyIDs.contains) ?? false) }
            .reduce(Int64(0)) { $0 + $1.cents }
        let income = transactions
            .filter { $0.type == .income }
            .reduce(Int64(0)) { $0 + $1.cents }
        return HomeSummary(
            totalBudgetCents: totalBudget,
            spentCents: spent,
            incomeCents: income,
            allocatedCents: monthlyBudget?.allocatedCents ?? 0
        )
    }

    static func cards(
        categories: [BudgetCategory],
        items: [MonthlyBudgetItem],
        transactions: [Transaction],
        savingOnly: Bool
    ) -> [CategoryCardModel] {
        categories
            .filter { !$0.isHidden && $0.isSavingCategory == savingOnly }
            .map { category in
                let item = items.first { $0.categoryID == category.categoryID }
                let spent = transactions
                    .filter { $0.type == .expense && $0.categoryID == category.categoryID }
                    .reduce(Int64(0)) { $0 + $1.cents }
                let budget = item?.adjustedCents ?? 0
                let remaining = budget - spent
                return CategoryCardModel(
                    categoryID: category.categoryID,
                    name: category.name,
                    icon: category.icon,
                    colorHex: category.colorHex,
                    budgetCents: budget,
                    spentCents: spent,
                    remainingCents: remaining,
                    usageRatio: budget > 0 ? Double(spent) / Double(budget) : 0,
                    status: status(remainingCents: remaining, adjustedCents: budget)
                )
            }
    }
}
