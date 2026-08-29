import Foundation
import SwiftData

enum TransactionType: String, Codable, Sendable, CaseIterable {
    case expense
    case income

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }
}

/// 分类的判定来源（规格第五节优先级：用户规则 > 历史 > 本地词库 > AI）。
enum ClassificationSource: String, Codable, Sendable, CaseIterable {
    case manual        // 用户手动选择
    case historyRule   // 历史消费记录匹配
    case builtinRule   // 内置商户词库
    case userRule      // 用户自定义规则（第二批）
    case ai            // AI 判断（预留）

    var title: String {
        switch self {
        case .manual: return "手动选择"
        case .historyRule: return "历史记录"
        case .builtinRule: return "内置词库"
        case .userRule: return "自定义规则"
        case .ai: return "AI"
        }
    }
}

/// 消费或收入记录（规格第二十七节 Transaction）。
/// 金额以「分」存储（正数），方向由 type 区分；year/month 由 date 派生，用于月度隔离。
@Model
final class Transaction {
    var transactionID: UUID = UUID()
    var typeRaw: String = TransactionType.expense.rawValue
    var cents: Int64 = 0
    var date: Date = Date()
    var year: Int = 0
    var month: Int = 0
    var merchant: String = ""
    var title: String = ""
    var note: String = ""
    var categoryID: UUID? = nil
    var accountID: UUID? = nil
    var classificationSourceRaw: String = ClassificationSource.manual.rawValue
    var confidence: Double = 1.0
    var isUserCorrected: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var classificationSource: ClassificationSource {
        get { ClassificationSource(rawValue: classificationSourceRaw) ?? .manual }
        set { classificationSourceRaw = newValue.rawValue }
    }

    init(
        type: TransactionType,
        cents: Int64,
        date: Date,
        merchant: String,
        title: String,
        note: String = "",
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        classificationSource: ClassificationSource = .manual,
        confidence: Double = 1.0,
        isUserCorrected: Bool = false
    ) {
        self.transactionID = UUID()
        self.type = type
        self.cents = cents
        self.date = date
        let budgetMonth = BudgetMonth(date: date)
        self.year = budgetMonth.year
        self.month = budgetMonth.month
        self.merchant = merchant
        self.title = title
        self.note = note
        self.categoryID = categoryID
        self.accountID = accountID
        self.classificationSource = classificationSource
        self.confidence = confidence
        self.isUserCorrected = isUserCorrected
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
