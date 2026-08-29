import SwiftUI
import SwiftData

/// 「分配预算」：把本月收入分配到各个分区（规格第十节）。
struct AllocationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query private var items: [MonthlyBudgetItem]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @State private var amounts: [UUID: String] = [:]
    @State private var errorMessage: String?

    private let month = BudgetMonth.current

    private var allocatable: [BudgetCategory] {
        categories.filter { !$0.isHidden }
    }

    private var incomeCents: Int64 {
        allTransactions
            .filter { $0.type == .income && $0.year == month.year && $0.month == month.month }
            .reduce(Int64(0)) { $0 + $1.cents }
    }

    private var parsedAmounts: [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for category in allocatable {
            result[category.categoryID] = Money(string: amounts[category.categoryID] ?? "")?.cents ?? 0
        }
        return result
    }

    private var totalAllocatedCents: Int64 {
        parsedAmounts.values.reduce(Int64(0)) { $0 + $1 }
    }

    private var unallocatedCents: Int64 {
        incomeCents - totalAllocatedCents
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(allocatable) { category in
                        allocationRow(category)
                    }
                } header: {
                    Text("为各分区分配本月预算（\(month.title)）")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本月收入 \(Money(cents: incomeCents).displayText) · 已分配 \(Money(cents: totalAllocatedCents).displayText)")
                        Text(
                            unallocatedCents >= 0
                                ? "剩余待分配 \(Money(cents: unallocatedCents).displayText)"
                                : "超出收入 \(Money(cents: -unallocatedCents).displayText)"
                        )
                        .foregroundStyle(unallocatedCents >= 0 ? Color.green : Color.red)
                        Text("未分配的金额不会被任何分区扣减，可以稍后再分配。本月还没有收入记录时，可先在「记一笔」里选择收入。")
                    }
                }
            }
            .navigationTitle("分配预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                }
            }
            .onAppear { loadAmountsIfNeeded() }
            .alert(
                "保存失败",
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

    // MARK: - 子视图

    private func allocationRow(_ category: BudgetCategory) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: category.colorHex).opacity(0.15))
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: category.colorHex))
            }
            .frame(width: 30, height: 30)
            Text(category.name)
            Spacer()
            TextField("0", text: binding(for: category.categoryID))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text("元")
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for categoryID: UUID) -> Binding<String> {
        Binding(
            get: { amounts[categoryID] ?? "" },
            set: { amounts[categoryID] = $0 }
        )
    }

    // MARK: - 动作

    private func loadAmountsIfNeeded() {
        guard amounts.isEmpty else { return }
        for category in allocatable {
            let initial = items.first {
                $0.categoryID == category.categoryID
                    && $0.year == month.year
                    && $0.month == month.month
            }?.initialCents
            let cents = initial ?? category.defaultMonthlyCents
            amounts[category.categoryID] = Money(cents: cents).inputText
        }
    }

    private func save() {
        let service = BudgetService(context: context)
        do {
            for category in allocatable {
                let cents = Money(string: amounts[category.categoryID] ?? "")?.cents ?? 0
                try service.setInitialAllocation(
                    categoryID: category.categoryID,
                    month: month,
                    cents: cents
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
