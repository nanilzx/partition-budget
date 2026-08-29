import SwiftUI
import SwiftData

/// 新建 / 编辑预算分区。
struct CategoryFormSheet: View {
    var editingCategory: BudgetCategory? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = "folder"
    @State private var colorHex = "#3B82F6"
    @State private var monthlyAmountString = ""
    @State private var carryOverEnabled = false
    @State private var isSavingCategory = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：餐饮、数码产品", text: $name)
                }
                Section("图标") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 48), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(CategoryIconCatalog.icons, id: \.self) { symbol in
                            iconCell(symbol)
                        }
                    }
                }
                Section("颜色") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 40), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(CategoryColorCatalog.colors, id: \.self) { hex in
                            colorCell(hex)
                        }
                    }
                }
                Section {
                    TextField("每月预算（元），可留空", text: $monthlyAmountString)
                        .keyboardType(.decimalPad)
                    Toggle("余额结转", isOn: $carryOverEnabled)
                    Toggle("储蓄类分区", isOn: $isSavingCategory)
                } header: {
                    Text("预算设置")
                } footer: {
                    Text("余额结转：本月没用完的预算自动加到下个月。储蓄类分区不计入日常可花金额，适合储蓄、应急金等。")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingCategory == nil ? "新建分区" : "编辑分区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                }
            }
            .onAppear { loadIfNeeded() }
        }
    }

    // MARK: - 子视图

    private func iconCell(_ symbol: String) -> some View {
        Button {
            icon = symbol
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 36)
                .background(
                    icon == symbol ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func colorCell(_ hex: String) -> some View {
        Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(
                        colorHex == hex ? Color.primary : Color.clear,
                        lineWidth: 2
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private func loadIfNeeded() {
        guard let category = editingCategory, name.isEmpty else { return }
        name = category.name
        icon = category.icon
        colorHex = category.colorHex
        monthlyAmountString = category.defaultMonthlyCents == 0
            ? ""
            : Money(cents: category.defaultMonthlyCents).inputText
        carryOverEnabled = category.carryOverEnabled
        isSavingCategory = category.isSavingCategory
    }

    private func save() {
        do {
            let cents = Money(string: monthlyAmountString)?.cents ?? 0
            let service = BudgetService(context: context)
            if let category = editingCategory {
                try service.updateCategory(
                    category,
                    name: name,
                    icon: icon,
                    colorHex: colorHex,
                    defaultMonthlyCents: cents,
                    carryOverEnabled: carryOverEnabled,
                    isSavingCategory: isSavingCategory
                )
            } else {
                try service.createCategory(
                    name: name,
                    icon: icon,
                    colorHex: colorHex,
                    defaultMonthlyCents: cents,
                    carryOverEnabled: carryOverEnabled,
                    isSavingCategory: isSavingCategory
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum CategoryIconCatalog {
    static let icons = [
        "fork.knife", "cup.and.saucer", "cart", "bag",
        "bus", "car", "gamecontroller", "theatermasks",
        "music.note", "airplane", "house", "creditcard",
        "heart", "gift", "laptopcomputer", "book",
        "graduationcap", "camera", "dog", "figure.walk",
        "pills", "banknote", "piggybank", "briefcase",
        "wrench.and.screwdriver", "phone",
    ]
}

enum CategoryColorCatalog {
    static let colors = [
        "#EF4444", "#F97316", "#F59E0B", "#22C55E",
        "#14B8A6", "#3B82F6", "#6366F1", "#8B5CF6",
        "#EC4899", "#64748B", "#0EA5E9", "#84CC16",
    ]
}
