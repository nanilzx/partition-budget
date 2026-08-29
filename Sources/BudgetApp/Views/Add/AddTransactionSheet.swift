import SwiftUI
import SwiftData

/// 「记一笔」：新增与编辑共用。最少只需金额 + 描述，分类由推荐预选。
/// 传入 capture 时为「截图/短信识别的待确认入账」模式。
struct AddTransactionSheet: View {
    var editingTransaction: Transaction? = nil
    var capture: CapturePrefill? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var allCategories: [BudgetCategory]

    @State private var model = AddTransactionModel()
    @State private var saveError: String?

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
                Section("备注（可选）") {
                    TextField("备注", text: $model.note, axis: .vertical)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { attemptSave() }
                        .disabled(!model.canSave)
                }
            }
            .onAppear {
                if let capture {
                    model.load(capture: capture)
                    model.suggestCategory(context: context)
                } else {
                    model.load(editingTransaction: editingTransaction)
                }
            }
            .confirmationDialog(overBudgetTitle, isPresented: $model.showOverBudgetDialog, titleVisibility: .visible) {
                Button("仍然记录（余额将为负）") {
                    do {
                        try model.save(context: context)
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

    private var amountSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $model.amountString)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
            }
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
            TextField("消费内容（如：麦当劳午饭）", text: $model.merchantText)
                .onChange(of: model.merchantText) { _, _ in
                    model.suggestCategory(context: context)
                }
            categoryPicker
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

    private var categoryPicker: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
            spacing: 8
        ) {
            ForEach(visibleCategories) { category in
                categoryChip(category)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryChip(_ category: BudgetCategory) -> some View {
        let selected = model.selectedCategoryID == category.categoryID
        return Button {
            model.selectCategory(category)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color(hex: category.colorHex) : Color(hex: category.colorHex).opacity(0.12)
            )
            .foregroundStyle(selected ? Color.white : Color(hex: category.colorHex))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            if dialogShown { return }
            try model.save(context: context)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
