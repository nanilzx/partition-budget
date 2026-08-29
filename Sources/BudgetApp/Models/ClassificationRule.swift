import Foundation
import SwiftData

/// 用户自定义分类规则（规格第六节）。
/// 优先级永远高于历史记录、内置词库与 AI：用户把某个商户纠正过一次，
/// 以后输入同样的内容就固定推荐到纠正后的分区。
@Model
final class ClassificationRule {
    var ruleID: UUID = UUID()
    var keyword: String = ""       // 小写存储，用于大小写无关匹配
    var categoryID: UUID = UUID()
    var createdAt: Date = Date()

    init(keyword: String, categoryID: UUID) {
        self.ruleID = UUID()
        self.keyword = keyword
        self.categoryID = categoryID
        self.createdAt = Date()
    }
}

extension ClassificationRule {
    static func all(in context: ModelContext) throws -> [ClassificationRule] {
        try context.fetch(
            FetchDescriptor<ClassificationRule>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }
}
