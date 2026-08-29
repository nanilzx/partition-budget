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
/// 优先级（规格第五/六节）：用户自定义规则 > 历史消费记录 > 内置词库。
/// 用户纠正（手动改分区）会自动生成自定义规则，之后同样内容固定推荐到纠正后的分区。
/// 第二批接入 AI Provider 时，在此方法内部按优先级插入即可，UI 无需改动。
struct ClassificationService {
    let context: ModelContext

    func suggest(text: String, categories: [BudgetCategory]) -> ClassificationResult? {
        let query = normalized(text)
        guard !query.isEmpty else { return nil }

        if let fromRules = suggestFromUserRules(query: query, categories: categories) {
            return fromRules
        }
        if let fromHistory = suggestFromHistory(query: query, categories: categories) {
            return fromHistory
        }
        if let fromBuiltin = suggestFromBuiltinRules(query: query, categories: categories) {
            return fromBuiltin
        }
        return nil
    }

    // MARK: - 用户自定义规则（最高优先级）

    func allRules() throws -> [ClassificationRule] {
        try ClassificationRule.all(in: context)
    }

    /// 同一关键词只保留一条规则，重复添加即覆盖。
    @discardableResult
    func upsertRule(keyword: String, categoryID: UUID) throws -> ClassificationRule? {
        let key = normalized(keyword)
        guard key.count >= 2 else { return nil }
        if let existing = try allRules().first(where: { $0.keyword == key }) {
            existing.categoryID = categoryID
            existing.createdAt = Date()
            try context.save()
            return existing
        }
        let rule = ClassificationRule(keyword: key, categoryID: categoryID)
        context.insert(rule)
        try context.save()
        return rule
    }

    func deleteRule(_ rule: ClassificationRule) throws {
        context.delete(rule)
        try context.save()
    }

    private func suggestFromUserRules(query: String, categories: [BudgetCategory]) -> ClassificationResult? {
        guard let rules = try? allRules() else { return nil }
        for rule in rules {
            let keyword = rule.keyword
            guard keyword.count >= 2,
                  query.contains(keyword) || keyword.contains(query) else { continue }
            guard let category = categories.first(where: { $0.categoryID == rule.categoryID }) else {
                continue
            }
            return ClassificationResult(
                categoryID: category.categoryID,
                categoryName: category.name,
                source: .userRule,
                confidence: 0.95
            )
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
