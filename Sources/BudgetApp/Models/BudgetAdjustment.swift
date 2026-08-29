import Foundation
import SwiftData

enum AdjustmentType: String, Codable, Sendable, CaseIterable {
    case initial       // 本月预算初始化
    case manual        // 用户手动调整 / 分配修改
    case transferIn    // 预算转移转入
    case transferOut   // 预算转移转出
    case carryOver     // 上月余额结转

    var title: String {
        switch self {
        case .initial: return "初始化"
        case .manual: return "手动调整"
        case .transferIn: return "转移转入"
        case .transferOut: return "转移转出"
        case .carryOver: return "余额结转"
        }
    }
}

/// 预算台账（规格第十八节）：除消费外，每一笔预算金额变化都必须在这里留痕，
/// 不能只保存当前余额。
@Model
final class BudgetAdjustment {
    var adjustmentID: UUID = UUID()
    var categoryID: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var cents: Int64 = 0
    var typeRaw: String = AdjustmentType.manual.rawValue
    var reason: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    var relatedID: UUID? = nil

    var type: AdjustmentType {
        get { AdjustmentType(rawValue: typeRaw) ?? .manual }
        set { typeRaw = newValue.rawValue }
    }

    init(
        categoryID: UUID,
        year: Int,
        month: Int,
        cents: Int64,
        type: AdjustmentType,
        reason: String,
        date: Date = Date(),
        relatedID: UUID? = nil
    ) {
        self.adjustmentID = UUID()
        self.categoryID = categoryID
        self.year = year
        self.month = month
        self.cents = cents
        self.type = type
        self.reason = reason
        self.date = date
        self.relatedID = relatedID
        self.createdAt = Date()
    }
}
