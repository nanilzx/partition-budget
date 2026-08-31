import SwiftUI
import SwiftData

/// 预算 Tab：月度概览、分区管理（增删改/排序/隐藏）、预算转移入口。
struct BudgetView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query private var items: [MonthlyBudgetItem]

    @Query private var monthlyBudgets: [MonthlyBudget]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @Query private var savingGoals: [SavingGoal]

    @State private var showingCategoryForm = false
    @State private var editingCategory: BudgetCategory?
    @State private var showingTransfer = false
    @State private var deleteCandidate: BudgetCategory?
    @State private var showDeleteConfirm = false
    @State private var showInUseAlert = false
    @State private var errorMessage: String?

    private let month = BudgetMonth.current

    private var currentBudget: MonthlyBudget? {
        monthlyBudgets.first { $0.year == month.year && $0.month == month.month }
    }

    private var incomeCents: Int64 {
        allTransactions
            .filter { $0.type == .income && $0.year == month.year && $0.month == month.month }
            .reduce(Int64(0)) { $0 + $1.cents }
    }

    private var unallocatedCents: Int64 {
        incomeCents - (currentBudget?.allocatedCents ?? 0)
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                categorySection
                toolsSection
            }
            .dsGlassListSurface()
            .navigationTitle("预算")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCategoryForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingCategoryForm) { CategoryFormSheet() }
            .sheet(item: $editingCategory) { category in
                CategoryFormSheet(editingCategory: category)
            }
            .sheet(isPresented: $showingTransfer) { TransferSheet() }
            .confirmationDialog(
                "确认删除分区",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除「\(deleteCandidate?.name ?? "")」", role: .destructive) {
                    performDelete()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("该分区没有任何消费记录，可以安全删除。")
            }
            .alert("无法删除", isPresented: $showInUseAlert) {
                Button("改为隐藏分区") {
                    if let candidate = deleteCandidate {
                        try? BudgetService(context: context).setCategoryHidden(candidate, hidden: true)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                if let candidate = deleteCandidate {
                    let count = allTransactions.filter { $0.categoryID == candidate.categoryID }.count
                    let goalCount = savingGoals.filter { $0.categoryID == candidate.categoryID }.count
                    Text(inUseMessage(category: candidate, transactionCount: count, goalCount: goalCount))
                }
            }
            .alert(
                "出错了",
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

    // MARK: - 分区

    private var overviewSection: some View {
        Section {
            LabeledContent("本月收入") {
                Text(Money(cents: incomeCents).displayText)
            }
            LabeledContent("已分配") {
                Text(Money(cents: currentBudget?.allocatedCents ?? 0).displayText)
            }
            LabeledContent("未分配") {
                Text(Money(cents: unallocatedCents).displayText)
                    .foregroundStyle(unallocatedCents < 0 ? Color.red : Color.primary)
            }
        } header: {
            Text("本月预算（\(month.title)）")
        } footer: {
            Text("点按首页顶部卡片进入「分配本月预算」。未分配 = 本月收入 − 已分配。")
                .listRowBackground(Color.clear)
        }
        .dsGlassRowCard()
    }

    private var categorySection: some View {
        Section {
            ForEach(categories) { category in
                categoryRow(category)
            }
            .onMove(perform: moveCategories)
        } header: {
            Text("预算分区")
        } footer: {
            Text("长按拖动调整顺序；左滑可隐藏或删除（有消费记录的分区只能隐藏）。")
                .listRowBackground(Color.clear)
        }
        .dsGlassRowCard()
    }

    private var toolsSection: some View {
        Section {
            Button {
                showingTransfer = true
            } label: {
                Label("预算转移", systemImage: "arrow.left.arrow.right")
            }
            NavigationLink {
                SavingGoalListView()
            } label: {
                Label("储蓄目标", systemImage: "target")
            }
        } header: {
            Text("工具")
        } footer: {
            Text("在分区之间重新分配本月剩余额度；为储蓄分区设立目标并追踪进度。")
                .listRowBackground(Color.clear)
        }
        .dsGlassRowCard()
    }

    private func categoryRow(_ category: BudgetCategory) -> some View {
        let item = items.first {
            $0.categoryID == category.categoryID
                && $0.year == month.year
                && $0.month == month.month
        }
        let spent = allTransactions
            .filter {
                $0.type == .expense
                    && $0.categoryID == category.categoryID
                    && $0.year == month.year
                    && $0.month == month.month
            }
            .reduce(Int64(0)) { $0 + $1.cents }
        let remaining = (item?.adjustedCents ?? 0) - spent

        return Button {
            editingCategory = category
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: category.colorHex).opacity(0.15))
                    Image(systemName: category.icon)
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: category.colorHex))
                }
                .frame(width: 34, height: 34)
                HStack(spacing: 6) {
                    Text(category.name)
                        .foregroundStyle(category.isHidden ? Color.secondary : Color.primary)
                    if category.isSavingCategory {
                        tag("储蓄", color: .green)
                    }
                    if category.carryOverEnabled {
                        tag("结转", color: .blue)
                    }
                    if category.isHidden {
                        tag("已隐藏", color: .gray)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money(cents: remaining).displayText)
                        .fontWeight(.semibold)
                        .foregroundStyle(remaining < 0 ? Color.red : Color.primary)
                    Text(item == nil ? "本月未分配" : "本月剩余")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                requestDelete(category)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                try? BudgetService(context: context).setCategoryHidden(category, hidden: !category.isHidden)
            } label: {
                Label(category.isHidden ? "显示" : "隐藏", systemImage: category.isHidden ? "eye" : "eye.slash")
            }
            .tint(.indigo)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - 动作

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        try? BudgetService(context: context).reorder(ordered)
    }

    private func requestDelete(_ category: BudgetCategory) {
        deleteCandidate = category
        let count = allTransactions.filter { $0.categoryID == category.categoryID }.count
        let goalCount = savingGoals.filter { $0.categoryID == category.categoryID }.count
        if count > 0 || goalCount > 0 {
            showInUseAlert = true
        } else {
            showDeleteConfirm = true
        }
    }

    private func inUseMessage(
        category: BudgetCategory,
        transactionCount: Int,
        goalCount: Int
    ) -> String {
        var reasons: [String] = []
        if transactionCount > 0 { reasons.append("\(transactionCount) 笔消费记录") }
        if goalCount > 0 { reasons.append("\(goalCount) 个储蓄目标") }
        return "「\(category.name)」还有\(reasons.joined(separator: "和"))。你可以改为隐藏分区，相关数据会完整保留。"
    }

    private func performDelete() {
        guard let candidate = deleteCandidate else { return }
        do {
            try BudgetService(context: context).deleteCategory(candidate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
