import SwiftUI
import SwiftData

/// 首页：只回答一个问题——每个用途的钱还剩多少。
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query private var items: [MonthlyBudgetItem]

    @Query private var monthlyBudgets: [MonthlyBudget]

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]

    @State private var selectedMonth = BudgetMonth.current
    @State private var showingAddSheet = false
    @State private var showingAllocation = false
    @State private var editing: Transaction?
    @State private var detailCategory: BudgetCategory?

    private var monthTransactions: [Transaction] {
        allTransactions.filter { $0.year == selectedMonth.year && $0.month == selectedMonth.month }
    }

    private var monthItems: [MonthlyBudgetItem] {
        items.filter { $0.year == selectedMonth.year && $0.month == selectedMonth.month }
    }

    private var selectedMonthlyBudget: MonthlyBudget? {
        monthlyBudgets.first { $0.year == selectedMonth.year && $0.month == selectedMonth.month }
    }

    private var summary: HomeSummary {
        HomeCalculator.summarize(
            categories: categories,
            items: monthItems,
            monthlyBudget: selectedMonthlyBudget,
            transactions: monthTransactions
        )
    }

    private var recentTransactions: [Transaction] { monthTransactions }

    /// 实际资产（规格第十一节）：与预算分开统计，只计「计入总资产」的账户。
    private var netWorthCents: Int64? {
        guard !accounts.isEmpty else { return nil }
        var deltas: [UUID: Int64] = [:]
        for txn in allTransactions {
            guard let id = txn.accountID else { continue }
            deltas[id, default: 0] += (txn.type == .income ? txn.cents : -txn.cents)
        }
        let total = accounts
            .filter(\.includeInNetWorth)
            .reduce(Int64(0)) { $0 + $1.openingBalanceCents + (deltas[$1.accountID] ?? 0) }
        return total
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthNavigator
                    if categories.isEmpty {
                        emptyState
                    } else {
                        OverviewHeaderView(summary: summary, netWorthCents: netWorthCents) { showingAllocation = true }
                        addTransactionButton
                        dailySection
                        savingSection
                        recentSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分区预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) { AddTransactionSheet() }
            .sheet(isPresented: $showingAllocation) { AllocationView() }
            .sheet(item: $editing) { txn in
                AddTransactionSheet(editingTransaction: txn)
            }
            .sheet(item: $detailCategory) { category in
                CategoryTransactionsSheet(category: category, month: selectedMonth)
            }
        }
    }

    // MARK: - 子视图

    private var monthNavigator: some View {
        HStack {
            monthButton("chevron.left") { selectedMonth = selectedMonth.previous }
            Spacer()
            Text(selectedMonth.title)
                .font(.headline)
            Spacer()
            if selectedMonth < BudgetMonth.current {
                monthButton("chevron.right") { selectedMonth = selectedMonth.next }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
    }

    private func monthButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var addTransactionButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("记一笔", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    private var dailySection: some View {
        let cards = HomeCalculator.cards(
            categories: categories,
            items: monthItems,
            transactions: monthTransactions,
            savingOnly: false
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text("日常预算")
                .font(.title3.weight(.semibold))
            if cards.isEmpty {
                sectionEmptyHint("还没有日常预算分区，去「预算」页创建")
            }
            ForEach(cards) { card in
                BudgetCategoryCardView(card: card) {
                    detailCategory = categories.first { $0.categoryID == card.categoryID }
                }
            }
        }
    }

    private var savingSection: some View {
        let cards = HomeCalculator.cards(
            categories: categories,
            items: monthItems,
            transactions: monthTransactions,
            savingOnly: true
        )
        return Group {
            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("储蓄 · 不计入日常可花")
                        .font(.title3.weight(.semibold))
                    ForEach(cards) { card in
                        BudgetCategoryCardView(card: card) {
                            detailCategory = categories.first { $0.categoryID == card.categoryID }
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近消费").font(.title3.weight(.semibold))
                Spacer()
                if !recentTransactions.isEmpty {
                    Button("查看全部") { router.selectedTab = .transactions }
                        .font(.subheadline)
                }
            }
            if recentTransactions.isEmpty {
                sectionEmptyHint("本月还没有记录，点上方「记一笔」开始")
            } else {
                VStack(spacing: 0) {
                    let latest = Array(recentTransactions.prefix(5))
                    ForEach(Array(latest.enumerated()), id: \.element.transactionID) { index, txn in
                        TransactionRowView(transaction: txn, categories: categories) {
                            editing = txn
                        }
                        if index < latest.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("开始分区预算")
                .font(.title3.bold())
            Text("把每个月的钱分到不同用途，\n随时看到每份还剩多少。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("去创建预算分区") { router.selectedTab = .budget }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func sectionEmptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
