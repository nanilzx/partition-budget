import SwiftUI
import SwiftData

/// 首页：只回答一个问题——每个用途的钱还剩多少。
/// 结构参照 Apple Health/Wallet：大数字焦点 + 轻量列表分区，无卡片堆叠。
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

    /// 实际资产（规格第十一节）：与预算分开统计，只计「计入总资产」的账户。
    private var netWorthCents: Int64? {
        guard !accounts.isEmpty else { return nil }
        var deltas: [UUID: Int64] = [:]
        for txn in allTransactions {
            guard let id = txn.accountID else { continue }
            deltas[id, default: 0] += (txn.type == .income ? txn.cents : -txn.cents)
        }
        return accounts
            .filter(\.includeInNetWorth)
            .reduce(Int64(0)) { $0 + $1.openingBalanceCents + (deltas[$1.accountID] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            if categories.isEmpty {
                emptyState
            } else {
                homeList
            }
        }
        .sheet(isPresented: $showingAddSheet) { AddTransactionSheet() }
        .sheet(isPresented: $showingAllocation) { AllocationView(month: selectedMonth) }
    }

    // MARK: - 主列表

    private var homeList: some View {
        List {
            heroSection
            dailySection
            savingSection
        }
        .dsGlassListSurface()
        .dsMinimizeTabBarOnScroll()
        .navigationTitle("分区预算")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            floatingAddButton
        }
    }

    /// 悬浮玻璃「记一笔」：整个 App 最重要的操作。
    private var floatingAddButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("记一笔", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
        }
        .dsGlass(.interactive, in: Capsule())
        .foregroundStyle(.primary)
        .padding(.trailing, DS.padding)
        .padding(.bottom, 6)
    }

    /// 顶部：月份切换（玻璃容器）+ 「本月还可使用」大数字焦点，浮在内容之上。
    /// List 已为分组内容提供统一的左右边距；行内左右必须为 0，避免再次缩进后比下方卡片窄。
    private var heroSection: some View {
        Section {
            // 月份切换按钮与分配入口不能互相嵌套，否则 List 会出现点击命中冲突。
            VStack(alignment: .leading, spacing: 6) {
                monthNavigator
                Button {
                    DS.Haptic.tap()
                    showingAllocation = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            selectedMonth == BudgetMonth.current
                                ? "本月还可使用"
                                : "\(selectedMonth.month)月还可使用"
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(Money(cents: summary.remainingCents).displayText)
                            .font(.system(size: 50, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(summary.remainingCents < 0 ? Color.red : Color.primary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: summary.remainingCents)
                        Text("已使用 \(Money(cents: summary.spentCents).displayText) · 总预算 \(Money(cents: summary.totalBudgetCents).displayText) · 未分配 \(Money(cents: summary.unallocatedCents).displayText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let netWorthCents {
                            Text("实际资产 \(Money(cents: netWorthCents).displayText)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .dsGlass(.regular, in: RoundedRectangle(cornerRadius: DS.glassCornerRadius))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 0))
        }
    }

    private var monthNavigator: some View {
        dsGlassContainer(spacing: 14) {
            HStack {
                Button {
                    selectedMonth = selectedMonth.previous
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                // List 行内多个按钮必须显式 plain，否则整行都会触发第一个按钮
                .buttonStyle(.plain)
                .dsGlass(.interactive, in: Circle())
                .foregroundStyle(.primary)
                Spacer()
                VStack(spacing: 0) {
                    Text("\(selectedMonth.month)月")
                        .font(.headline)
                    Text(String(selectedMonth.year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Group {
                    if selectedMonth < BudgetMonth.current {
                        Button {
                            selectedMonth = selectedMonth.next
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .dsGlass(.interactive, in: Circle())
                        .foregroundStyle(.primary)
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var dailySection: some View {
        let cards = HomeCalculator.cards(
            categories: categories,
            items: monthItems,
            transactions: monthTransactions,
            savingOnly: false
        )
        return Section("预算分区") {
            ForEach(cards) { card in
                NavigationLink {
                    if let category = categories.first(where: { $0.categoryID == card.categoryID }) {
                        BudgetDetailView(category: category, month: selectedMonth)
                    }
                } label: {
                    BudgetCategoryRowView(card: card)
                }
            }
        }
        .dsGlassRowCard()
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
                Section("储蓄") {
                    ForEach(cards) { card in
                        NavigationLink {
                            if let category = categories.first(where: { $0.categoryID == card.categoryID }) {
                                BudgetDetailView(category: category, month: selectedMonth)
                            }
                        } label: {
                            BudgetCategoryRowView(card: card)
                        }
                    }
                }
                .dsGlassRowCard()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("开始分区预算", systemImage: "wallet.pass")
        } description: {
            Text("把每个月的钱分到不同用途，随时看到每份还剩多少。")
        } actions: {
            Button("去创建预算分区") {
                router.selectedTab = .budget
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
