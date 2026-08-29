import Foundation
import SwiftData

/// 资金账户管理（规格第十二节）。删除账户只解绑交易、不删除记录，
/// 保证消费历史永不失效。
struct AccountService {
    let context: ModelContext

    @discardableResult
    func create(
        name: String,
        type: AccountType,
        icon: String,
        openingBalanceCents: Int64,
        includeInNetWorth: Bool
    ) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServiceError.invalidName }
        let all = try Account.all(in: context)
        guard !all.contains(where: { $0.name == trimmed }) else {
            throw ServiceError.duplicateName(trimmed)
        }
        let account = Account(
            name: trimmed,
            type: type,
            icon: icon,
            openingBalanceCents: openingBalanceCents,
            includeInNetWorth: includeInNetWorth,
            sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(account)
        try context.save()
        return account
    }

    func update(
        _ account: Account,
        name: String? = nil,
        type: AccountType? = nil,
        icon: String? = nil,
        openingBalanceCents: Int64? = nil,
        includeInNetWorth: Bool? = nil
    ) throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ServiceError.invalidName }
            let clash = try Account.all(in: context).contains {
                $0.name == trimmed && $0.accountID != account.accountID
            }
            guard !clash else { throw ServiceError.duplicateName(trimmed) }
            account.name = trimmed
        }
        if let type {
            account.type = type
            account.icon = Account.defaultIcon(for: type, keeping: account.icon)
        }
        if let icon { account.icon = icon }
        if let openingBalanceCents { account.openingBalanceCents = openingBalanceCents }
        if let includeInNetWorth { account.includeInNetWorth = includeInNetWorth }
        account.updatedAt = Date()
        try context.save()
    }

    /// 删除账户：关联交易只解绑（accountID 置空），记录本身保留。
    func delete(_ account: Account) throws {
        let id = account.accountID
        let linked = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.accountID == id }
        for txn in linked {
            txn.accountID = nil
            txn.updatedAt = Date()
        }
        context.delete(account)
        try context.save()
    }

    /// 余额 = 期初余额 + 关联交易（收入加、支出减）。
    func balanceCents(of account: Account, transactions: [Transaction]) -> Int64 {
        let id = account.accountID
        let delta = transactions
            .filter { $0.accountID == id }
            .reduce(Int64(0)) { $0 + ($1.type == .income ? $1.cents : -$1.cents) }
        return account.openingBalanceCents + delta
    }

    /// 全部账户的余额表（一次遍历）。
    func balanceTable(transactions: [Transaction]) throws -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for account in try Account.all(in: context) {
            result[account.accountID] = balanceCents(of: account, transactions: transactions)
        }
        return result
    }

    /// 总资产：只统计「计入总资产」的账户。
    func netWorthCents(transactions: [Transaction]) throws -> Int64 {
        let table = try balanceTable(transactions: transactions)
        return try Account.all(in: context)
            .filter(\.includeInNetWorth)
            .reduce(Int64(0)) { $0 + (table[$1.accountID] ?? 0) }
    }
}

extension Account {
    /// 换类型时若图标还是旧类型的默认图标，跟随新类型；自定义过则保留。
    static func defaultIcon(for type: AccountType, keeping current: String) -> String {
        let allDefaults: Set<String> = ["banknote", "building.columns", "creditcard", "iphone", "wallet.pass"]
        return allDefaults.contains(current) ? type.defaultIcon : current
    }
}
