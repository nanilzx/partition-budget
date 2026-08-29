import Foundation

/// 记录页筛选条件（规格第二十节：类型/分区/金额范围/关键词/时间范围）。
/// 时间范围由视图层的「本月 / 全部时间」切换承担。
struct TransactionFilter: Equatable {
    var type: TransactionType? = nil
    var categoryID: UUID? = nil
    var minCents: Int64? = nil
    var maxCents: Int64? = nil

    var hasActiveFilters: Bool {
        type != nil || categoryID != nil || minCents != nil || maxCents != nil
    }
}
