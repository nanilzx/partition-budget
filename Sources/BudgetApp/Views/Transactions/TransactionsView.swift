import SwiftUI
import SwiftData

/// 记录 Tab：全部收支、搜索、筛选、编辑、删除。
struct TransactionsView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @State private var searchText = ""
    @State private var scopeAll = false
    @State private var selectedMonth = BudgetMonth.current
    @State private var filter = TransactionFilter()
    @State private var showingFilter = false
    @State private var editing: Transaction?
    @State private var pendingDelete: Transaction?

    private var filtered: [Transaction] {
        var result = scopeAll
            ? allTransactions
            : allTransactions.filter { $0.year == selectedMonth.year && $0.month == selectedMonth.month }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { txn in
                txn.title.lowercased().contains(query)
                    || txn.merchant.lowercased().contains(query)
                    || txn.note.lowercased().contains(query)
            }
        }
        if let type = filter.type {
            result = result.filter { $0.type == type }
        }
        if let cid = filter.categoryID {
            result = result.filter { $0.categoryID == cid }
        }
        if let minCents = filter.minCents {
            result = result.filter { $0.cents >= minCents }
        }
        if let maxCents = filter.maxCents {
            result = result.filter { $0.cents <= maxCents }
        }
        return result
    }

    private var totalExpenseCents: Int64 {
        filtered.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.cents }
    }

    private var totalIncomeCents: Int64 {
        filtered.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.cents }
    }

    var body: some View {
        NavigationStack {
            List {
                scopeSection
                Section {
                    ForEach(filtered) { txn in
                        TransactionRowView(transaction: txn, categories: categories) {
                            editing = txn
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = txn
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("共 \(filtered.count) 笔")
                        Spacer()
                        Text("支出 \(Money(cents: totalExpenseCents).displayText)")
                        Text("收入 \(Money(cents: totalIncomeCents).displayText)")
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                    .textCase(nil)
                }
                if filtered.isEmpty {
                    Section {
                        Text("没有符合条件的记录")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "搜索 麦当劳 / Steam / 备注…")
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFilter = true
                    } label: {
                        Image(
                            systemName: filter.hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
            }
            .sheet(isPresented: $showingFilter) {
                TransactionFilterSheet(filter: $filter)
            }
            .sheet(item: $editing) { txn in
                AddTransactionSheet(editingTransaction: txn)
            }
            .confirmationDialog(
                "删除这笔记录？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let txn = pendingDelete {
                        try? TransactionService(context: context).delete(txn)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("支出记录删除后，对应分区的余额会自动恢复。")
            }
        }
    }

    // MARK: - 子视图

    private var scopeSection: some View {
        Section {
            HStack {
                if scopeAll {
                    Button("查看本月") {
                        scopeAll = false
                        selectedMonth = .current
                    }
                    Spacer()
                } else {
                    Button {
                        selectedMonth = selectedMonth.previous
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(selectedMonth.title)
                        .font(.headline)
                    Spacer()
                    if selectedMonth < BudgetMonth.current {
                        Button {
                            selectedMonth = selectedMonth.next
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    } else {
                        Color.clear.frame(width: 28, height: 28)
                    }
                    Spacer()
                }
                Button(scopeAll ? "本月" : "全部") {
                    scopeAll.toggle()
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
    }
}
