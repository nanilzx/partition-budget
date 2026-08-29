import Foundation

/// 业务层错误：文案直接面向用户展示。
enum ServiceError: LocalizedError {
    case invalidAmount
    case invalidName
    case duplicateName(String)
    case categoryNotFound
    case categoryInUse(Int)
    case transferSameCategory
    case transferExceedsRemaining

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "金额必须大于 0"
        case .invalidName:
            return "名称不能为空"
        case .duplicateName(let name):
            return "已存在同名分区「\(name)」"
        case .categoryNotFound:
            return "找不到对应的预算分区"
        case .categoryInUse(let count):
            return "该分区下还有 \(count) 笔消费记录，删除会导致记录失效"
        case .transferSameCategory:
            return "不能在同一个分区之间转移"
        case .transferExceedsRemaining:
            return "转移金额超过来源分区的剩余额度"
        }
    }
}
