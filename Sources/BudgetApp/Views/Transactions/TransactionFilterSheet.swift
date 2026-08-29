import SwiftUI
import SwiftData

/// 记录筛选：类型 / 预算分区 / 金额范围，点「应用」生效。
struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter

    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @State private var typeIndex = 0
    @State private var categoryID: UUID?
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $typeIndex) {
                        Text("全部").tag(0)
                        Text("支出").tag(1)
                        Text("收入").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section("预算分区") {
                    Picker("分区", selection: $categoryID) {
                        Text("全部分区").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.categoryID))
                        }
                    }
                }
                Section("金额范围（元）") {
                    TextField("最小金额", text: $minText)
                        .keyboardType(.decimalPad)
                    TextField("最大金额", text: $maxText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("重置") {
                        typeIndex = 0
                        categoryID = nil
                        minText = ""
                        maxText = ""
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用") {
                        apply()
                        dismiss()
                    }
                }
            }
            .onAppear { load() }
        }
    }

    // MARK: - 动作

    private func load() {
        switch filter.type {
        case .expense: typeIndex = 1
        case .income: typeIndex = 2
        default: typeIndex = 0
        }
        categoryID = filter.categoryID
        minText = filter.minCents.map { Money(cents: $0).inputText } ?? ""
        maxText = filter.maxCents.map { Money(cents: $0).inputText } ?? ""
    }

    private func apply() {
        filter.type = typeIndex == 1 ? .expense : (typeIndex == 2 ? .income : nil)
        filter.categoryID = categoryID
        // 输入不合法时忽略该条件
        filter.minCents = Money(string: minText)?.cents
        filter.maxCents = Money(string: maxText)?.cents
    }
}
