import XCTest
import SwiftData
@testable import BudgetApp

/// 资金账户：余额派生、删除解绑、总资产（规格第十一、十二节）。
final class AccountServiceTests: ServiceTestCase {

    func makeAccount(name: String, openingYuan: Int64, include: Bool = true) throws -> Account {
        try accounts.create(
            name: name, type: .bank, icon: "building.columns",
            openingBalanceCents: Money(yuan: openingYuan).cents,
            includeInNetWorth: include
        )
    }

    // 余额 = 期初 + 收入 − 支出
    func testBalanceDerivedFromTransactions() throws {
        let account = try makeAccount(name: "微信零钱", openingYuan: 8000)
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)

        try transactions.addExpense(
            cents: 3600, description: "麦当劳", categoryID: dining.categoryID,
            date: date(2026, 8, 10), accountID: account.accountID
        )
        try transactions.addIncome(
            cents: 50000, description: "兼职", date: date(2026, 8, 15), accountID: account.accountID
        )

        let all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(accounts.balanceCents(of: account, transactions: all), 846400)
    }

    // 修改/删除交易后余额自动重算（派生）
    func testBalanceRecomputesAfterEditAndDelete() throws {
        let account = try makeAccount(name: "支付宝", openingYuan: 1000)
        let shopping = try makeCategory(name: "购物", monthlyYuan: 800)
        try months.ensureMonthlyBudget(for: m)

        let txn = try transactions.addExpense(
            cents: 10000, description: "淘宝", categoryID: shopping.categoryID,
            date: date(2026, 8, 10), accountID: account.accountID
        )
        var all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(accounts.balanceCents(of: account, transactions: all), 90000)

        try transactions.update(txn, cents: 15000)
        all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(accounts.balanceCents(of: account, transactions: all), 85000)

        try transactions.delete(txn)
        all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(accounts.balanceCents(of: account, transactions: all), 100000)
    }

    // 删除账户只解绑交易，记录保留（记录永不失效）
    func testDeleteAccountUnlinksTransactions() throws {
        let account = try makeAccount(name: "招行卡", openingYuan: 5000)
        let dining = try makeCategory(name: "餐饮", monthlyYuan: 1000)
        try months.ensureMonthlyBudget(for: m)
        try transactions.addExpense(
            cents: 3600, description: "麦当劳", categoryID: dining.categoryID,
            date: date(2026, 8, 10), accountID: account.accountID
        )

        try accounts.delete(account)

        XCTAssertTrue(try Account.all(in: context).isEmpty)
        let txns = try months.monthTransactions(m)
        XCTAssertEqual(txns.count, 1)
        XCTAssertNil(txns.first?.accountID)
        XCTAssertEqual(try months.remainingCents(categoryID: dining.categoryID, month: m), 96400)
    }

    // 总资产只计「计入总资产」的账户
    func testNetWorthExcludesExcludedAccounts() throws {
        _ = try makeAccount(name: "银行卡", openingYuan: 8000, include: true)
        _ = try makeAccount(name: "公积金", openingYuan: 30000, include: false)

        let all: [Transaction] = []
        let netWorth = try accounts.netWorthCents(transactions: all)
        XCTAssertEqual(netWorth, 800000)
    }

    func testDuplicateAccountNameRejected() throws {
        _ = try makeAccount(name: "微信零钱", openingYuan: 0)
        XCTAssertThrowsError(
            try makeAccount(name: "微信零钱", openingYuan: 0)
        )
    }
}
