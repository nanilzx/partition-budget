import Foundation
import SwiftData

struct ClassificationResult {
    let categoryID: UUID
    let categoryName: String
    let source: ClassificationSource
    let confidence: Double

    /// 置信度低于 70% 时 UI 必须让用户确认（规格第五节）。
    var isLowConfidence: Bool { confidence < 0.7 }
}

/// 消费分类推荐。
/// 优先级（规格第五/六节）：用户自定义规则（第二批）> 历史消费记录 > 内置词库。
/// 用户在历史里纠正过的分类会通过「历史记录」层自动生效——
/// 例如把 Steam 从购物改到娱乐后，之后输入 "Steam Games" 也会推荐娱乐。
/// 第二批接入用户规则与 AI Provider 时，在此方法内部按优先级插入即可，UI 无需改动。
struct ClassificationService {
    let context: ModelContext

    func suggest(text: String, categories: [BudgetCategory]) -> ClassificationResult? {
        let query = normalized(text)
        guard !query.isEmpty else { return nil }

        if let fromHistory = suggestFromHistory(query: query, categories: categories) {
            return fromHistory
        }
        if let fromBuiltin = suggestFromBuiltinRules(query: query, categories: categories) {
            return fromBuiltin
        }
        return nil
    }

    /// 历史优先：从最近的记录里找商户/描述互相包含的记录，沿用它的分区。
    private func suggestFromHistory(query: String, categories: [BudgetCategory]) -> ClassificationResult? {
        guard let recent = try? context.fetch(
            FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ) else { return nil }

        for transaction in recent.prefix(300) {
            let merchant = normalized(transaction.merchant)
            guard merchant.count >= 2,
                  query.contains(merchant) || merchant.contains(query) else { continue }
            guard let category = categories.first(where: { $0.categoryID == transaction.categoryID }) else {
                continue
            }
            return ClassificationResult(
                categoryID: category.categoryID,
                categoryName: category.name,
                source: .historyRule,
                confidence: 0.9
            )
        }
        return nil
    }

    /// 内置词库：命中关键词后，按「最长关键词优先」确定标准分区名。
    private func suggestFromBuiltinRules(query: String, categories: [BudgetCategory]) -> ClassificationResult? {
        var bestKeyword = ""
        var bestCanonical = ""
        for rule in BuiltinClassificationRules.rules where query.contains(rule.keyword) {
            if rule.keyword.count > bestKeyword.count {
                bestKeyword = rule.keyword
                bestCanonical = rule.canonical
            }
        }
        guard !bestKeyword.isEmpty,
              let category = categories.first(where: { $0.name == bestCanonical }) else { return nil }
        return ClassificationResult(
            categoryID: category.categoryID,
            categoryName: category.name,
            source: .builtinRule,
            confidence: 0.8
        )
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
