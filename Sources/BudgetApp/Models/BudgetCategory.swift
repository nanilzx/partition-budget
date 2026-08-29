import Foundation
import SwiftData

/// 预算分区（规格第二十七节 BudgetCategory）。
/// 「当前余额 / 已消费 / 使用比例」按月存放在 MonthlyBudgetItem 中；
/// 分区本身只保存配置（名称、图标、颜色、默认月预算、结转开关等）。
@Model
final class BudgetCategory {
    var categoryID: UUID = UUID()
    var name: String = ""
    var icon: String = "folder"
    var colorHex: String = "#3B82F6"
    var defaultMonthlyCents: Int64 = 0
    var carryOverEnabled: Bool = false
    var isSavingCategory: Bool = false
    var sortOrder: Int = 0
    var isHidden: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        icon: String,
        colorHex: String,
        defaultMonthlyCents: Int64,
        carryOverEnabled: Bool = false,
        isSavingCategory: Bool = false,
        sortOrder: Int = 0,
        isHidden: Bool = false
    ) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.defaultMonthlyCents = defaultMonthlyCents
        self.carryOverEnabled = carryOverEnabled
        self.isSavingCategory = isSavingCategory
        self.sortOrder = sortOrder
        self.isHidden = isHidden
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension BudgetCategory {
    static func all(in context: ModelContext) throws -> [BudgetCategory] {
        try context.fetch(
            FetchDescriptor<BudgetCategory>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            )
        )
    }

    static func byID(_ id: UUID, in context: ModelContext) throws -> BudgetCategory? {
        try all(in: context).first { $0.categoryID == id }
    }
}
