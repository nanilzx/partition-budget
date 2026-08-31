import SwiftUI
import SwiftData

/// 储蓄目标（规格第十七节）：进度 = 储蓄分区累积余额 ÷ 目标金额，附预计完成时间。
struct SavingGoalListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\SavingGoal.createdAt)])
    private var goals: [SavingGoal]

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query private var items: [MonthlyBudgetItem]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @State private var editing: SavingGoal?
    @State private var showingForm = false

    private let month = BudgetMonth.current

    /// 储蓄分区的累积余额（逐月结转形成蓄水池）。
    private func currentCents(for goal: SavingGoal) -> Int64 {
        guard let item = items.first(where: {
            $0.categoryID == goal.categoryID && $0.year == month.year && $0.month == month.month
        }) else { return 0 }
        let spent = allTransactions
            .filter {
                $0.type == .expense
                    && $0.categoryID == goal.categoryID
                    && $0.year == month.year
                    && $0.month == month.month
            }
            .reduce(Int64(0)) { $0 + $1.cents }
        return item.adjustedCents - spent
    }

    private func monthlyContributionCents(for goal: SavingGoal) -> Int64 {
        guard let category = categories.first(where: { $0.categoryID == goal.categoryID }) else { return 0 }
        return category.defaultMonthlyCents
    }

    private func estimatedText(for goal: SavingGoal, current: Int64) -> String? {
        guard current < goal.targetCents else { return "已达成 🎉" }
        let monthly = monthlyContributionCents(for: goal)
        guard monthly > 0 else { return nil }
        let monthsNeeded = Int(ceil(Double(goal.targetCents - current) / Double(monthly)))
        guard monthsNeeded > 0 else { return nil }
        return "按每月 \(Money(cents: monthly).displayText) 投入，约 \(monthsNeeded) 个月达成"
    }

    var body: some View {
        List {
            Section {
                if goals.isEmpty {
                    Text("还没有储蓄目标。给自己立一个，比如「电脑基金」「旅行基金」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(goals) { goal in
                    Button {
                        editing = goal
                    } label: {
                        goalRow(goal)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            try? SavingGoalService(context: context).delete(goal)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("进度来自对应储蓄分区的累积余额（含结转）。给储蓄分区设置每月默认预算，就能自动估算完成时间。")
                    .listRowBackground(Color.clear)
            }
            .dsGlassRowCard()
        }
        .dsGlassListSurface()
        .navigationTitle("储蓄目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(savingCategories.isEmpty)
            }
        }
        .sheet(isPresented: $showingForm) {
            SavingGoalFormSheet()
        }
        .sheet(item: $editing) { goal in
            SavingGoalFormSheet(editingGoal: goal)
        }
    }

    private var savingCategories: [BudgetCategory] {
        categories.filter { $0.isSavingCategory && !$0.isHidden }
    }

    private func goalRow(_ goal: SavingGoal) -> some View {
        let current = currentCents(for: goal)
        let ratio = goal.targetCents > 0 ? Double(max(current, 0)) / Double(goal.targetCents) : 0
        let category = categories.first { $0.categoryID == goal.categoryID }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let category {
                    Image(systemName: category.icon)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: category.colorHex))
                }
                Text(goal.name)
                    .font(.subheadline)
                Spacer()
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ratio >= 1 ? Color.green : Color.secondary)
            }
            Text("\(Money(cents: current).displayText) / \(Money(cents: goal.targetCents).displayText)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.quaternarySystemFill))
                    Capsule()
                        .fill(Color.green)
                        .frame(width: proxy.size.width * min(ratio, 1))
                }
            }
            .frame(height: DS.barHeight)
            if let estimated = estimatedText(for: goal, current: current) {
                Text(estimated)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let date = goal.targetDate {
                Text("目标日期：\(dateText(date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

/// 新建 / 编辑储蓄目标。
struct SavingGoalFormSheet: View {
    var editingGoal: SavingGoal? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @State private var name = ""
    @State private var categoryID: UUID?
    @State private var targetAmountString = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Date()
    @State private var errorMessage: String?

    private var savingCategories: [BudgetCategory] {
        categories.filter { $0.isSavingCategory }
    }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 1
            && categoryID != nil
            && (Money(string: targetAmountString)?.cents ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    TextField("如：电脑基金、旅行基金", text: $name)
                    if savingCategories.isEmpty {
                        Text("请先在分区管理里创建一个「储蓄类分区」，再添加目标。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Picker("储蓄分区", selection: $categoryID) {
                            Text("选择分区").tag(UUID?.none)
                            ForEach(savingCategories) { category in
                                Text(category.name).tag(Optional(category.categoryID))
                            }
                        }
                    }
                }
                Section {
                    TextField("目标金额（元）", text: $targetAmountString)
                        .keyboardType(.decimalPad)
                    Toggle("设定目标日期", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("目标日期", selection: $targetDate, displayedComponents: .date)
                    }
                } header: {
                    Text("金额")
                } footer: {
                    Text("进度按储蓄分区的累积余额计算；不设目标日期也可以，会按每月默认投入估算完成时间。")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingGoal == nil ? "新建目标" : "编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadIfNeeded() }
        }
    }

    private func loadIfNeeded() {
        guard let goal = editingGoal, name.isEmpty else { return }
        name = goal.name
        categoryID = goal.categoryID
        targetAmountString = Money(cents: goal.targetCents).inputText
        if let date = goal.targetDate {
            hasTargetDate = true
            targetDate = date
        }
    }

    private func save() {
        guard let target = categoryID, let cents = Money(string: targetAmountString)?.cents, cents > 0 else { return }
        do {
            let service = SavingGoalService(context: context)
            if let goal = editingGoal {
                try service.update(
                    goal,
                    name: name,
                    categoryID: target,
                    targetCents: cents,
                    targetDate: hasTargetDate ? .some(targetDate) : .some(nil)
                )
            } else {
                try service.create(
                    name: name,
                    categoryID: target,
                    targetCents: cents,
                    targetDate: hasTargetDate ? targetDate : nil
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
