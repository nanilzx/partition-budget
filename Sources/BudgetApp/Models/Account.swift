import Foundation
import SwiftData

enum AccountType: String, Codable, Sendable, CaseIterable {
    case cash
    case bank
    case credit
    case alipay
    case wechat
    case other

    var title: String {
        switch self {
        case .cash: return "现金"
        case .bank: return "银行卡"
        case .credit: return "信用卡"
        case .alipay: return "支付宝"
        case .wechat: return "微信"
        case .other: return "其他"
        }
    }

    var defaultIcon: String {
        switch self {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .credit: return "creditcard"
        case .alipay, .wechat: return "iphone"
        case .other: return "wallet.pass"
        }
    }
}

/// 实际资金账户（规格第十二节）。预算系统与账户系统保持逻辑独立：
/// 一个账户可以承担多个预算，一个预算也可以从多个账户消费。
/// 余额 = 期初余额 + 关联交易求和（收入加、支出减），由交易派生，保证编辑/删除后不漂移。
@Model
final class Account {
    var accountID: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.bank.rawValue
    var icon: String = "creditcard"
    var openingBalanceCents: Int64 = 0
    var includeInNetWorth: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .bank }
        set { typeRaw = newValue.rawValue }
    }

    init(
        name: String,
        type: AccountType,
        icon: String,
        openingBalanceCents: Int64 = 0,
        includeInNetWorth: Bool = true,
        sortOrder: Int = 0
    ) {
        self.accountID = UUID()
        self.name = name
        self.type = type
        self.icon = icon
        self.openingBalanceCents = openingBalanceCents
        self.includeInNetWorth = includeInNetWorth
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Account {
    static func all(in context: ModelContext) throws -> [Account] {
        try context.fetch(
            FetchDescriptor<Account>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            )
        )
    }

    static func byID(_ id: UUID, in context: ModelContext) throws -> Account? {
        try all(in: context).first { $0.accountID == id }
    }
}
