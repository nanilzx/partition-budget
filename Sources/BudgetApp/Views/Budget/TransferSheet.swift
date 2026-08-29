import SwiftUI
import SwiftData

/// 预算转移：把来源分区某月的剩余额度转给目标分区（规格第九节）。
struct TransferSheet: View {
    var month: BudgetMonth = .current
    var prefilledToCategoryID: UUID? = nil
    var prefilledAmountCents: Int64? = nil
    var onCompleted: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query private var items: [MonthlyBudgetItem]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @State private var fromCategoryID: UUID?
    @State private var toCategoryID: UUID?
    @State private var amountString = ""
    @State private var note = ""
    @State private var errorMessage: String?

    private var visibleCategories: [BudgetCategory] {
        categories.filter { !$0.isHidden }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("从", selection: $fromCategoryID) {
                        Text("选择分区").tag(UUID?.none)
                        ForEach(visibleCategories) { category in
                            Text(category.name).tag(Optional(category.categoryID))
                        }
                    }
                    Picker("到", selection: $toCategoryID) {
                        Text("选择分区").tag(UUID?.none)
                        ForEach(visibleCategories) { category in
                            Text(category.name).tag(Optional(category.categoryID))
                        }
                    }
                } header: {
                    Text("转移方向（\(month.title)）")
                } footer: {
                    Text("这只是把本月额度在分区之间重新分配，不是银行卡转账。")
                }
                Section {
                    HStack {
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                        Text("元")
                            .foregroundStyle(.secondary)
                    }
                    TextField("原因（可选）", text: $note)
                } header: {
                    Text("金额")
                }
                if let preview = previewText {
                    Section {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("预算转移")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确认转移") { save() }
                        .disabled(!canTransfer)
                }
            }
            .onAppear { loadDefaults() }
            .alert(
                "无法转移",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 计算

    private func remainingCents(for categoryID: UUID?) -> Int64 {
        guard let id = categoryID,
              let item = items.first(where: {
                  $0.categoryID == id && $0.year == month.year && $0.month == month.month
              }) else { return 0 }
        let spent = allTransactions
            .filter {
                $0.type == .expense
                    && $0.categoryID == id
                    && $0.year == month.year
                    && $0.month == month.month
            }
            .reduce(Int64(0)) { $0 + $1.cents }
        return item.adjustedCents - spent
    }

    private func transferCents() -> Int64? {
        guard let cents = Money(string: amountString)?.cents, cents > 0 else { return nil }
        return cents
    }

    private var canTransfer: Bool {
        guard let from = fromCategoryID, let to = toCategoryID, from != to,
              let cents = transferCents() else { return false }
        return cents <= remainingCents(for: from)
    }

    private var previewText: String? {
        guard let from = fromCategoryID, let to = toCategoryID, from != to,
              let cents = transferCents() else { return nil }
        let fromName = categories.first { $0.categoryID == from }?.name ?? "—"
        let toName = categories.first { $0.categoryID == to }?.name ?? "—"
        let afterFrom = Money(cents: remainingCents(for: from) - cents).displayText
        let afterTo = Money(cents: remainingCents(for: to) + cents).displayText
        return "\(fromName) 转移后剩 \(afterFrom)；\(toName) 转移后剩 \(afterTo)"
    }

    // MARK: - 动作

    private func loadDefaults() {
        toCategoryID = toCategoryID ?? prefilledToCategoryID
        if let cents = prefilledAmountCents, amountString.isEmpty {
            amountString = Money(cents: cents).inputText
        }
    }

    private func save() {
        guard let from = fromCategoryID, let to = toCategoryID, let cents = transferCents() else { return }
        do {
            try BudgetService(context: context).transfer(
                fromCategoryID: from,
                toCategoryID: to,
                cents: cents,
                month: month,
                note: note
            )
            DS.Haptic.success()
            dismiss()
            onCompleted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
