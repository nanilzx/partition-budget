import SwiftUI
import SwiftData

/// 记录 Tab：全部收支、搜索、筛选、编辑、删除。
/// 交互全部走 iOS 原生习惯：searchable / swipeActions / contextMenu。
struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]

    @State private var searchText = ""
    @State private var scopeAll = false
    @State private var selectedMonth = BudgetMonth.current
    @State private var filter = TransactionFilter()
    @State private var showingFilter = false
    @State private var showingAddSheet = false
    @State private var showingStats = false
    @State private var editing: Transaction?
    @State private var pendingDelete: Transaction?
    @State private var quickCategoryTarget: Transaction?

    private var hasActiveConditions: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || filter.hasActiveFilters
            || scopeAll
            || selectedMonth != BudgetMonth.current
    }

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
            Group {
                if filtered.isEmpty && !hasActiveConditions {
                    ContentUnavailableView {
                        Label("暂无消费记录", systemImage: "list.bullet")
                    } description: {
                        Text("记录第一笔消费后，会显示在这里。")
                    } actions: {
                        Button("记一笔") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    listContent
                }
            }
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingStats = true
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
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
            .searchable(text: $searchText, prompt: "搜索 麦当劳 / Steam / 备注…")
            .sheet(isPresented: $showingFilter) {
                TransactionFilterSheet(filter: $filter)
            }
            .sheet(isPresented: $showingStats) {
                StatsView(month: selectedMonth)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddTransactionSheet()
            }
            .sheet(item: $editing) { txn in
                AddTransactionSheet(editingTransaction: txn)
            }
            .sheet(item: $quickCategoryTarget) { txn in
                QuickCategorySheet(transaction: txn)
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
                        DS.Haptic.destructive()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("支出记录删除后，对应分区的余额会自动恢复。")
            }
        }
    }

    // MARK: - 列表

    private var listContent: some View {
        List {
            scopeSection
            Section {
                ForEach(filtered) { txn in
                    TransactionRowView(transaction: txn, categories: categories, accounts: accounts) {
                        editing = txn
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = txn
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            quickCategoryTarget = txn
                        } label: {
                            Label("分类", systemImage: "tag")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button {
                            editing = txn
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            quickCategoryTarget = txn
                        } label: {
                            Label("修改分类", systemImage: "tag")
                        }
                        Button(role: .destructive) {
                            pendingDelete = txn
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .dsGlassRowCard()
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
                .dsGlassRowCard()
            }
        }
        .listStyle(.insetGrouped)
        .dsGlassListSurface()
    }

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

/// 右滑快速修改分类（规格第十七节）。
private struct QuickCategorySheet: View {
    let transaction: Transaction

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories.filter { !$0.isHidden }) { category in
                        Button {
                            try? TransactionService(context: context).update(
                                transaction,
                                categoryID: category.categoryID
                            )
                            DS.Haptic.success()
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: category.icon)
                                    .font(.footnote)
                                    .foregroundStyle(Color(hex: category.colorHex))
                                    .frame(width: 24)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if transaction.categoryID == category.categoryID {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("改为其他分类后，两边的预算会立即重算，并记住你的偏好。")
                }
            }
            .navigationTitle("修改分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
