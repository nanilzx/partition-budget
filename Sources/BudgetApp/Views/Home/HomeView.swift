import SwiftUI
import SwiftData
import PhotosUI

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
    @State private var showingPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var recognizeError: String?
    @State private var editing: Transaction?

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
        .sheet(isPresented: $showingAllocation) { AllocationView() }
        .sheet(item: $editing) { txn in
            AddTransactionSheet(editingTransaction: txn)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, newItem in
            guard let item = newItem else { return }
            pickedItem = nil
            Task { await recognize(from: item) }
        }
        .alert(
            "截图识别",
            isPresented: Binding(
                get: { recognizeError != nil },
                set: { if !$0 { recognizeError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(recognizeError ?? "")
        }
    }

    // MARK: - 主列表

    private var homeList: some View {
        List {
            heroSection
            dailySection
            savingSection
            recentSection
        }
        .dsMinimizeTabBarOnScroll()
        .navigationTitle("分区预算")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            floatingButtons
        }
        .overlay {
            if isRecognizing {
                recognizingOverlay
            }
        }
    }

    /// 悬浮玻璃按钮组：截图识别 + 记一笔（整个 App 最重要的两个操作）。
    private var floatingButtons: some View {
        VStack(spacing: 10) {
            Button {
                showingPhotoPicker = true
                DS.Haptic.tap()
            } label: {
                Label("截图识别", systemImage: "doc.text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .dsGlass(.interactive, in: Capsule())
            .foregroundStyle(.primary)

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
        }
        .padding(.trailing, DS.padding)
        .padding(.bottom, 6)
    }

    private var recognizingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("正在本机识别截图…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .dsGlass(.regular, in: RoundedRectangle(cornerRadius: DS.glassCornerRadius))
    }

    /// 相册选图 → 本机 OCR → 弹出确认单。
    @MainActor
    private func recognize(from item: PhotosPickerItem) async {
        isRecognizing = true
        defer { isRecognizing = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            recognizeError = "读取图片失败，请重试。"
            return
        }
        if let prefill = await ScreenshotOCR.recognizePrefill(in: image) {
            CaptureIntake.shared.present(prefill)
        } else {
            recognizeError = "未能从截图识别出金额。\n请换一张「付款成功」页面再试，或手动记一笔。"
        }
    }

    /// 顶部：月份切换（玻璃容器）+ 「本月还可使用」大数字焦点，浮在内容之上。
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                monthNavigator
                Text("本月还可使用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(Money(cents: summary.remainingCents).displayText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsGlass(.regular, in: RoundedRectangle(cornerRadius: DS.glassCornerRadius))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
            }
        }
    }

    private var recentSection: some View {
        Section {
            if monthTransactions.isEmpty {
                Text("本月还没有记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(monthTransactions.prefix(5)), id: \.transactionID) { txn in
                TransactionRowView(transaction: txn, categories: categories, accounts: accounts) {
                    editing = txn
                }
            }
            Button {
                router.selectedTab = .transactions
            } label: {
                Text("查看全部记录")
                    .font(.subheadline)
            }
            .foregroundStyle(.tint)
        } header: {
            Text("最近消费")
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
