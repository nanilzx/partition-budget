import SwiftUI
import SwiftData

/// 某个预算分区的消费记录（规格第二节：查看该预算下所有消费记录）。
struct CategoryTransactionsSheet: View {
    let category: BudgetCategory
    let month: BudgetMonth

    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query private var items: [MonthlyBudgetItem]

    @State private var editing: Transaction?

    private var categoryTransactions: [Transaction] {
        allTransactions.filter { $0.categoryID == category.categoryID }
    }

    private var monthItem: MonthlyBudgetItem? {
        items.first {
            $0.categoryID == category.categoryID
                && $0.year == month.year
                && $0.month == month.month
        }
    }

    private var monthSpentCents: Int64 {
        categoryTransactions
            .filter { $0.type == .expense && $0.year == month.year && $0.month == month.month }
            .reduce(Int64(0)) { $0 + $1.cents }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("本月预算") {
                        Text(Money(cents: monthItem?.adjustedCents ?? 0).displayText)
                    }
                    LabeledContent("本月剩余") {
                        Text(Money(cents: (monthItem?.adjustedCents ?? 0) - monthSpentCents).displayText)
                            .foregroundStyle((monthItem?.adjustedCents ?? 0) - monthSpentCents < 0 ? Color.red : Color.primary)
                    }
                    LabeledContent("全部记录") {
                        Text("\(categoryTransactions.count) 笔")
                    }
                } header: {
                    Text(category.name)
                } footer: {
                    Text("余额由当月全部消费自动计算，修改或删除记录后会立即重算。")
                }
                Section {
                    ForEach(categoryTransactions) { txn in
                        TransactionRowView(transaction: txn, categories: [category]) {
                            editing = txn
                        }
                    }
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editing) { txn in
                AddTransactionSheet(editingTransaction: txn)
            }
        }
    }
}
