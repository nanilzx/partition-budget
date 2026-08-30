import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

/// 本地备份（规格第二十三节）：全量 JSON 导出 + 覆盖式导入。
/// 架构上保留未来迁移 CloudKit 同步的可能（字段与本地模型一一对应）。
enum BackupService {

    struct BackupCategory: Codable {
        var id: UUID
        var name: String
        var icon: String
        var colorHex: String
        var defaultMonthlyCents: Int64
        var carryOverEnabled: Bool
        var isSavingCategory: Bool
        var sortOrder: Int
        var isHidden: Bool
    }

    struct BackupTransaction: Codable {
        var id: UUID
        var type: String
        var cents: Int64
        var date: Date
        var merchant: String
        var title: String
        var note: String
        var categoryID: UUID?
        var accountID: UUID?
        var source: String
        var confidence: Double
        var isUserCorrected: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    struct BackupMonthlyBudget: Codable {
        var id: UUID
        var year: Int
        var month: Int
        var allocatedCents: Int64
    }

    struct BackupItem: Codable {
        var id: UUID
        var monthlyBudgetID: UUID
        var year: Int
        var month: Int
        var categoryID: UUID
        var initialCents: Int64
        var adjustedCents: Int64
        var carryOverCents: Int64
    }

    struct BackupTransfer: Codable {
        var id: UUID
        var fromCategoryID: UUID
        var toCategoryID: UUID
        var cents: Int64
        var date: Date
        var note: String
    }

    struct BackupAdjustment: Codable {
        var id: UUID
        var categoryID: UUID
        var year: Int
        var month: Int
        var cents: Int64
        var type: String
        var reason: String
        var date: Date
        var relatedID: UUID?
    }

    struct BackupRule: Codable {
        var id: UUID
        var keyword: String
        var categoryID: UUID
        var createdAt: Date
    }

    struct BackupAccount: Codable {
        var id: UUID
        var name: String
        var type: String
        var icon: String
        var openingBalanceCents: Int64
        var includeInNetWorth: Bool
        var sortOrder: Int
    }

    struct BackupFile: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var categories: [BackupCategory] = []
        var transactions: [BackupTransaction] = []
        var monthlyBudgets: [BackupMonthlyBudget] = []
        var items: [BackupItem] = []
        var transfers: [BackupTransfer] = []
        var adjustments: [BackupAdjustment] = []
        var rules: [BackupRule] = []
        var accounts: [BackupAccount] = []
    }

    // MARK: - 导出

    static func export(context: ModelContext) throws -> Data {
        var file = BackupFile()
        for c in try BudgetCategory.all(in: context) {
            file.categories.append(BackupCategory(
                id: c.categoryID, name: c.name, icon: c.icon, colorHex: c.colorHex,
                defaultMonthlyCents: c.defaultMonthlyCents, carryOverEnabled: c.carryOverEnabled,
                isSavingCategory: c.isSavingCategory, sortOrder: c.sortOrder, isHidden: c.isHidden
            ))
        }
        let txns = try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.createdAt)]))
        for t in txns {
            file.transactions.append(BackupTransaction(
                id: t.transactionID, type: t.typeRaw, cents: t.cents, date: t.date,
                merchant: t.merchant, title: t.title, note: t.note,
                categoryID: t.categoryID, accountID: t.accountID,
                source: t.classificationSourceRaw, confidence: t.confidence,
                isUserCorrected: t.isUserCorrected, createdAt: t.createdAt, updatedAt: t.updatedAt
            ))
        }
        for b in try context.fetch(FetchDescriptor<MonthlyBudget>()) {
            file.monthlyBudgets.append(BackupMonthlyBudget(
                id: b.monthlyBudgetID, year: b.year, month: b.month, allocatedCents: b.allocatedCents
            ))
        }
        for i in try context.fetch(FetchDescriptor<MonthlyBudgetItem>()) {
            file.items.append(BackupItem(
                id: i.itemID, monthlyBudgetID: i.monthlyBudgetID, year: i.year, month: i.month,
                categoryID: i.categoryID, initialCents: i.initialCents,
                adjustedCents: i.adjustedCents, carryOverCents: i.carryOverCents
            ))
        }
        for t in try context.fetch(FetchDescriptor<BudgetTransfer>()) {
            file.transfers.append(BackupTransfer(
                id: t.transferID, fromCategoryID: t.fromCategoryID, toCategoryID: t.toCategoryID,
                cents: t.cents, date: t.date, note: t.note
            ))
        }
        for a in try context.fetch(FetchDescriptor<BudgetAdjustment>()) {
            file.adjustments.append(BackupAdjustment(
                id: a.adjustmentID, categoryID: a.categoryID, year: a.year, month: a.month,
                cents: a.cents, type: a.typeRaw, reason: a.reason, date: a.date, relatedID: a.relatedID
            ))
        }
        for r in try ClassificationRule.all(in: context) {
            file.rules.append(BackupRule(
                id: r.ruleID, keyword: r.keyword, categoryID: r.categoryID, createdAt: r.createdAt
            ))
        }
        for a in try Account.all(in: context) {
            file.accounts.append(BackupAccount(
                id: a.accountID, name: a.name, type: a.typeRaw, icon: a.icon,
                openingBalanceCents: a.openingBalanceCents,
                includeInNetWorth: a.includeInNetWorth, sortOrder: a.sortOrder
            ))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    // MARK: - 导入（覆盖式恢复）

    static func importReplace(data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: BackupFile
        do {
            file = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw ServiceError.invalidBackupFile
        }

        // 先清空现有数据，再按备份重建
        try wipe(context: context)

        for c in file.categories {
            let model = BudgetCategory(
                name: c.name, icon: c.icon, colorHex: c.colorHex,
                defaultMonthlyCents: c.defaultMonthlyCents,
                carryOverEnabled: c.carryOverEnabled, isSavingCategory: c.isSavingCategory,
                sortOrder: c.sortOrder, isHidden: c.isHidden
            )
            model.categoryID = c.id
            context.insert(model)
        }
        for a in file.accounts {
            let model = Account(
                name: a.name, type: AccountType(rawValue: a.type) ?? .bank, icon: a.icon,
                openingBalanceCents: a.openingBalanceCents,
                includeInNetWorth: a.includeInNetWorth, sortOrder: a.sortOrder
            )
            model.accountID = a.id
            context.insert(model)
        }
        for b in file.monthlyBudgets {
            let model = MonthlyBudget(year: b.year, month: b.month)
            model.monthlyBudgetID = b.id
            model.allocatedCents = b.allocatedCents
            context.insert(model)
        }
        for i in file.items {
            let model = MonthlyBudgetItem(
                monthlyBudgetID: i.monthlyBudgetID, year: i.year, month: i.month,
                categoryID: i.categoryID, initialCents: i.initialCents, carryOverCents: i.carryOverCents
            )
            model.itemID = i.id
            model.adjustedCents = i.adjustedCents
            context.insert(model)
        }
        for t in file.transactions {
            let model = Transaction(
                type: TransactionType(rawValue: t.type) ?? .expense,
                cents: t.cents, date: t.date, merchant: t.merchant, title: t.title, note: t.note,
                categoryID: t.categoryID, accountID: t.accountID,
                classificationSource: ClassificationSource(rawValue: t.source) ?? .manual,
                confidence: t.confidence, isUserCorrected: t.isUserCorrected
            )
            model.transactionID = t.id
            model.createdAt = t.createdAt
            model.updatedAt = t.updatedAt
            context.insert(model)
        }
        for t in file.transfers {
            let model = BudgetTransfer(
                fromCategoryID: t.fromCategoryID, toCategoryID: t.toCategoryID,
                cents: t.cents, date: t.date, note: t.note
            )
            model.transferID = t.id
            context.insert(model)
        }
        for a in file.adjustments {
            let model = BudgetAdjustment(
                categoryID: a.categoryID, year: a.year, month: a.month, cents: a.cents,
                type: AdjustmentType(rawValue: a.type) ?? .manual,
                reason: a.reason, date: a.date, relatedID: a.relatedID
            )
            model.adjustmentID = a.id
            context.insert(model)
        }
        for r in file.rules {
            let model = ClassificationRule(keyword: r.keyword, categoryID: r.categoryID)
            model.ruleID = r.id
            model.createdAt = r.createdAt
            context.insert(model)
        }
        try context.save()
    }

    static func wipe(context: ModelContext) throws {
        let captures = try context.fetch(FetchDescriptor<CaptureInboxItem>())
        captures.forEach(context.delete)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        transactions.forEach(context.delete)
        let adjustments = try context.fetch(FetchDescriptor<BudgetAdjustment>())
        adjustments.forEach(context.delete)
        let transfers = try context.fetch(FetchDescriptor<BudgetTransfer>())
        transfers.forEach(context.delete)
        let items = try context.fetch(FetchDescriptor<MonthlyBudgetItem>())
        items.forEach(context.delete)
        let budgets = try context.fetch(FetchDescriptor<MonthlyBudget>())
        budgets.forEach(context.delete)
        let rules = try context.fetch(FetchDescriptor<ClassificationRule>())
        rules.forEach(context.delete)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        accounts.forEach(context.delete)
        let categories = try context.fetch(FetchDescriptor<BudgetCategory>())
        categories.forEach(context.delete)
        try context.save()
    }
}

/// 导出/导入使用的文件文档。
struct BudgetBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
