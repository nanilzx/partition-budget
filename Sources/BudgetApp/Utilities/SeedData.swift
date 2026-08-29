import Foundation
import SwiftData

/// 首次启动时写入的默认分区（规格第一节示例），金额只是起点，用户可随时修改。
enum SeedData {
    struct DefaultCategory {
        let name: String
        let icon: String
        let colorHex: String
        let monthlyYuan: Int64
        let carryOver: Bool
        let saving: Bool
    }

    static let defaults: [DefaultCategory] = [
        DefaultCategory(name: "餐饮", icon: "fork.knife", colorHex: "#F97316", monthlyYuan: 1200, carryOver: false, saving: false),
        DefaultCategory(name: "娱乐", icon: "gamecontroller", colorHex: "#8B5CF6", monthlyYuan: 500, carryOver: true, saving: false),
        DefaultCategory(name: "购物", icon: "cart", colorHex: "#EC4899", monthlyYuan: 800, carryOver: false, saving: false),
        DefaultCategory(name: "交通", icon: "bus", colorHex: "#3B82F6", monthlyYuan: 300, carryOver: false, saving: false),
        DefaultCategory(name: "社交", icon: "person.2", colorHex: "#14B8A6", monthlyYuan: 800, carryOver: false, saving: false),
        DefaultCategory(name: "固定支出", icon: "house", colorHex: "#64748B", monthlyYuan: 1500, carryOver: false, saving: false),
        DefaultCategory(name: "储蓄", icon: "piggybank", colorHex: "#22C55E", monthlyYuan: 1400, carryOver: true, saving: true),
    ]

    @discardableResult
    static func installDefaultCategoriesIfNeeded(context: ModelContext) throws -> Bool {
        let existing = try BudgetCategory.all(in: context)
        guard existing.isEmpty else { return false }

        for (index, item) in defaults.enumerated() {
            let category = BudgetCategory(
                name: item.name,
                icon: item.icon,
                colorHex: item.colorHex,
                defaultMonthlyCents: Money(yuan: item.monthlyYuan).cents,
                carryOverEnabled: item.carryOver,
                isSavingCategory: item.saving,
                sortOrder: index
            )
            context.insert(category)
        }
        try context.save()
        return true
    }
}
