import SwiftUI
import SwiftData

/// 用户自定义分类规则管理（规格第六节）。
struct RulesListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\ClassificationRule.createdAt, order: .reverse)])
    private var rules: [ClassificationRule]

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @State private var showingForm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    HStack(spacing: 10) {
                        Text(rule.keyword)
                            .font(.body)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let category = categories.first(where: { $0.categoryID == rule.categoryID }) {
                            Image(systemName: category.icon)
                                .font(.caption)
                                .foregroundStyle(Color(hex: category.colorHex))
                            Text(category.name)
                                .font(.subheadline)
                        } else {
                            Text("已删除分区")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            try? ClassificationService(context: context).deleteRule(rule)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("自定义规则")
            } footer: {
                Text("规则优先级最高：输入内容命中关键词时，永远推荐到规则指定的分区，高于历史记录和内置词库。你在记账时手动纠正分类也会自动生成规则。")
                    .listRowBackground(Color.clear)
            }
            .dsGlassRowCard()
        }
        .dsGlassListSurface()
        .navigationTitle("自定义分类规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(categories.isEmpty)
            }
        }
        .sheet(isPresented: $showingForm) {
            RuleFormSheet()
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

/// 新增规则：关键词 → 分区。
struct RuleFormSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @State private var keyword = ""
    @State private var categoryID: UUID?
    @State private var errorMessage: String?

    private var canSave: Bool {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && categoryID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("关键词（如：瑞幸、Steam）", text: $keyword)
                } header: {
                    Text("命中内容")
                } footer: {
                    Text("输入的消费内容包含该关键词（或关键词包含输入）时生效。")
                }
                Section("推荐到分区") {
                    Picker("分区", selection: $categoryID) {
                        Text("选择分区").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.categoryID))
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新增规则")
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
        }
    }

    private func save() {
        guard let target = categoryID else { return }
        do {
            try ClassificationService(context: context).upsertRule(
                keyword: keyword,
                categoryID: target
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
