import SwiftUI
import SwiftData

/// 预算分区详情（规格第二十二节）：剩余为焦点，下接总预算/已消费/细进度条/最近消费。
struct BudgetDetailView: View {
    let category: BudgetCategory
    let month: BudgetMonth

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query private var items: [MonthlyBudgetItem]

    @State private var editing: Transaction?
    @State private var showingAddSheet = false

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
            .filter {
                $0.categoryID == category.categoryID
                    && $0.year == month.year
                    && $0.month == month.month
            }
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
                .dsGlassRowCard()
            }
            Section("最近消费") {
                if recent.isEmpty {
                    Text("这个分区本月还没有消费记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .dsGlassRowCard()
                }
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, txn in
                    TransactionRowView(transaction: txn, categories: [category]) {
                        editing = txn
                    }
                    .dsGlassRowCard(position: .init(index: index, count: recent.count))
                }
            }
            Section {
                if month == BudgetMonth.current {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("在此分区记一笔", systemImage: "plus.circle")
                    }
                    .dsGlassRowCard(position: .first)
                }

                NavigationLink {
                    CategoryTransactionsView(category: category, month: month)
                } label: {
                    Label("查看本月全部记录", systemImage: "list.bullet")
                }
                .dsGlassRowCard(position: month == BudgetMonth.current ? .last : .single)
            }
        }
        .dsGlassListSurface()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { txn in
            AddTransactionSheet(editingTransaction: txn)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTransactionSheet(prefilledCategoryID: category.categoryID)
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

/// 当前分区当前月份的完整记录，避免从详情页跳到失去筛选条件的全局记录页。
private struct CategoryTransactionsView: View {
    let category: BudgetCategory
    let month: BudgetMonth

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @State private var editing: Transaction?

    private var transactions: [Transaction] {
        allTransactions.filter {
            $0.categoryID == category.categoryID
                && $0.year == month.year
                && $0.month == month.month
        }
    }

    var body: some View {
        List {
            Section {
                if transactions.isEmpty {
                    Text("这个分区本月还没有消费记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .dsGlassRowCard()
                } else {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        TransactionRowView(transaction: transaction, categories: [category]) {
                            editing = transaction
                        }
                        .dsGlassRowCard(position: .init(index: index, count: transactions.count))
                    }
                }
            } header: {
                Text("\(month.title) · 共 \(transactions.count) 笔")
            }
        }
        .dsGlassListSurface()
        .navigationTitle("\(category.name)记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { transaction in
            AddTransactionSheet(editingTransaction: transaction)
        }
    }
}
