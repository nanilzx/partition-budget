import SwiftUI
import SwiftData

/// 「记一笔」：新增与编辑共用，最少只需金额 + 描述。
/// 金额是整个 Sheet 的视觉核心（参考 Apple Pay 的大数字输入），底部一键确认。
struct AddTransactionSheet: View {
    var editingTransaction: Transaction? = nil
    var capture: CapturePrefill? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var allCategories: [BudgetCategory]

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]

    @State private var model = AddTransactionModel()
    @State private var saveError: String?
    @State private var showingCategoryPicker = false
    @FocusState private var amountFocused: Bool

    private var visibleCategories: [BudgetCategory] {
        allCategories.filter {
            !$0.isHidden || $0.categoryID == model.selectedCategoryID
        }
    }

    private var title: String {
        if editingTransaction != nil { return "编辑记录" }
        if capture != nil { return "确认消费" }
        return "记一笔"
    }

    private var confirmTitle: String {
        if editingTransaction != nil { return "保存修改" }
        if capture != nil { return "确认入账" }
        return model.isIncome ? "确认收入" : "确认记录"
    }

    private var selectedCategory: BudgetCategory? {
        allCategories.first { $0.categoryID == model.selectedCategoryID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if editingTransaction == nil {
                    Picker("类型", selection: $model.isIncome) {
                        Text("支出").tag(false)
                        Text("收入").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .onChange(of: model.isIncome) { _, _ in
                        model.clearSuggestion()
                    }
                }
                amountSection
                if model.isIncome {
                    incomeSection
                } else {
                    expenseSection
                }
                if !accounts.isEmpty {
                    Section("资金账户（可选）") {
                        Picker("支付账户", selection: $model.selectedAccountID) {
                            Text("不关联").tag(UUID?.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account.accountID))
                            }
                        }
                    }
                }
                Section("备注（可选）") {
                    TextField("备注", text: $model.note, axis: .vertical)
                }
                Section {
                    Button {
                        attemptSave()
                    } label: {
                        Text(confirmTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!model.canSave)
                    .listRowBackground(Color.accentColor)
                }
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { amountFocused = false }
                }
            }
            .onAppear {
                if let capture {
                    model.load(capture: capture)
                    model.suggestCategory(context: context)
                    amountFocused = true
                } else if editingTransaction == nil {
                    amountFocused = true
                } else {
                    model.load(editingTransaction: editingTransaction)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(
                    selection: $model.selectedCategoryID,
                    month: BudgetMonth(date: model.date)
                ) {
                    model.suggestCategory(context: context)
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(overBudgetTitle, isPresented: $model.showOverBudgetDialog, titleVisibility: .visible) {
                Button("仍然记录（余额将为负）") {
                    do {
                        try model.save(context: context)
                        DS.Haptic.success()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                Button("从其他分区转入差额") {
                    model.showTransferFix = true
                }
                Button("增加本月预算") {
                    do {
                        try model.saveWithBudgetBoost(context: context)
                        DS.Haptic.success()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                Button("更换分区") {}
                Button("取消", role: .cancel) {}
            } message: {
                Text(overBudgetMessage)
            }
            .sheet(isPresented: $model.showTransferFix) {
                TransferSheet(
                    month: BudgetMonth(date: model.date),
                    prefilledToCategoryID: model.selectedCategoryID,
                    prefilledAmountCents: model.overBudgetInfo?.shortfallCents
                ) {
                    do {
                        try model.save(context: context)
                        DS.Haptic.success()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
            .alert(
                "保存失败",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - 分区

    /// 金额输入：整个 Sheet 的视觉核心。
    private var amountSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("0", text: $model.amountString)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .focused($amountFocused)
                    .autocorrectionDisabled()
            }
            .padding(.vertical, 2)
        }
    }

    private var incomeSection: some View {
        Section("收入信息") {
            TextField("来源（如：工资）", text: $model.merchantText)
            DatePicker("日期", selection: $model.date, displayedComponents: .date)
        }
    }

    private var expenseSection: some View {
        Section("消费信息") {
            TextField("消费描述（如：麦当劳）", text: $model.merchantText)
                .onChange(of: model.merchantText) { _, _ in
                    model.suggestCategory(context: context)
                }
            categoryRow
            if let suggestion = model.suggestion {
                HStack(spacing: 6) {
                    Image(systemName: suggestion.isLowConfidence ? "questionmark.circle" : "sparkles")
                    Text(
                        suggestion.isLowConfidence
                            ? "可能属于「\(suggestion.categoryName)」，请确认"
                            : "已推荐「\(suggestion.categoryName)」（\(suggestion.source.title)）"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            DatePicker("日期", selection: $model.date, displayedComponents: .date)
        }
    }

    /// 分类行：原生行样式，点开轻量选择器（图标/名称/剩余预算）。
    private var categoryRow: some View {
        Button {
            showingCategoryPicker = true
            DS.Haptic.tap()
        } label: {
            HStack(spacing: 10) {
                if let category = selectedCategory {
                    Image(systemName: category.icon)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 24)
                    Text(category.name)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text("选择分区")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 超支确认

    private var overBudgetTitle: String {
        guard let info = model.overBudgetInfo else { return "预算不足" }
        return "「\(info.categoryName)」剩 \(Money(cents: info.remainingCents).displayText)，这笔要 \(Money(cents: info.amountCents).displayText)"
    }

    private var overBudgetMessage: String {
        let shortfall = Money(cents: model.overBudgetInfo?.shortfallCents ?? 0).displayText
        return "还差 \(shortfall)。预算是帮你做决策的，不会强制拦住你。"
    }

    private func attemptSave() {
        do {
            let dialogShown = try model.validate(context: context)
            if dialogShown {
                DS.Haptic.warning()
                return
            }
            try model.save(context: context)
            DS.Haptic.success()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// 轻量分类选择器：图标 + 名称 + 剩余预算（规格第七节）。
struct CategoryPickerSheet: View {
    @Binding var selection: UUID?
    let month: BudgetMonth
    var onPicked: () -> Void

    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query private var items: [MonthlyBudgetItem]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    private var visibleCategories: [BudgetCategory] {
        categories.filter { !$0.isHidden || $0.categoryID == selection }
    }

    private func remainingCents(of category: BudgetCategory) -> Int64? {
        guard let item = items.first(where: {
            $0.categoryID == category.categoryID
                && $0.year == month.year
                && $0.month == month.month
        }) else { return nil }
        let spent = allTransactions
            .filter {
                $0.type == .expense
                    && $0.categoryID == category.categoryID
                    && $0.year == month.year
                    && $0.month == month.month
            }
            .reduce(Int64(0)) { $0 + $1.cents }
        return item.adjustedCents - spent
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visibleCategories) { category in
                        Button {
                            selection = category.categoryID
                            DS.Haptic.tap()
                            onPicked()
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
                                if let remaining = remainingCents(of: category) {
                                    Text("剩 \(Money(cents: remaining).displayText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if selection == category.categoryID {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("选择后自动扣除该分区的预算。")
                }
            }
            .navigationTitle("选择分区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
