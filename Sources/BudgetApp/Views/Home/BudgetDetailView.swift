import SwiftUI
import SwiftData

/// 预算分区详情（规格第二十二节）：剩余为焦点，下接总预算/已消费/细进度条/最近消费。
struct BudgetDetailView: View {
    let category: BudgetCategory
    let month: BudgetMonth

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query private var items: [MonthlyBudgetItem]

    @State private var editing: Transaction?

    private var monthItem: MonthlyBudgetItem? {
        items.first {
            $0.categoryID == category.categoryID
                && $0.year == month.year
                && $0.month == month.month
        }
    }

    private var monthSpentCents: Int64 {
        allTransactions
            .filter {
                $0.type == .expense
                    && $0.categoryID == category.categoryID
                    && $0.year == month.year
                    && $0.month == month.month
            }
            .reduce(Int64(0)) { $0 + $1.cents }
    }

    private var budgetCents: Int64 { monthItem?.adjustedCents ?? 0 }
    private var remainingCents: Int64 { budgetCents - monthSpentCents }
    private var usageRatio: Double {
        budgetCents > 0 ? Double(monthSpentCents) / Double(budgetCents) : 0
    }

    private var recent: [Transaction] {
        allTransactions
            .filter { $0.categoryID == category.categoryID }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(remainingCents < 0 ? "已超支" : "剩余")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money(cents: remainingCents).displayText)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(remainingCents < 0 ? Color.red : Color.primary)
                        .contentTransition(.numericText())
                    Text("总预算 \(Money(cents: budgetCents).displayText) · 已消费 \(Money(cents: monthSpentCents).displayText)（\(Int((usageRatio * 100).rounded()))%）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    progressBar
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
            Section("最近消费") {
                if recent.isEmpty {
                    Text("这个分区本月还没有消费记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(recent) { txn in
                    TransactionRowView(transaction: txn, categories: [category]) {
                        editing = txn
                    }
                }
            }
            Section {
                Button {
                    router.selectedTab = .transactions
                } label: {
                    Label("查看全部记录", systemImage: "list.bullet")
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { txn in
            AddTransactionSheet(editingTransaction: txn)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.quaternarySystemFill))
                Capsule()
                    .fill(remainingCents < 0 ? Color.red : Color(hex: category.colorHex))
                    .frame(width: proxy.size.width * min(max(usageRatio, 0), 1))
            }
        }
        .frame(height: DS.barHeight)
        .animation(.easeOut(duration: 0.25), value: usageRatio)
    }
}
