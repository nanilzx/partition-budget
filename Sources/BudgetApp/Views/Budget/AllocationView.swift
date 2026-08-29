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
    @State private var incomeString = ""
    @State private var errorMessage: String?

    private let month = BudgetMonth.current

    private var allocatable: [BudgetCategory] {
        categories.filter { !$0.isHidden }
    }

    private var salaryIncome: Transaction? {
        allTransactions.first {
            $0.type == .income
                && $0.title == "工资"
                && $0.year == month.year
                && $0.month == month.month
        }
    }

    /// 收入模块里填的数字直接作为本月「工资」收入参与计算；输入不合法时回退已记录值。
    private var effectiveIncomeCents: Int64 {
        if let cents = Money(string: incomeString)?.cents { return cents }
        return salaryIncomeCents
    }

    private var salaryIncomeCents: Int64 {
        salaryIncome?.cents ?? 0
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
        effectiveIncomeCents - totalAllocatedCents
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("本月工资收入（元）", text: $incomeString)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("本月收入")
                } footer: {
                    Text("这里填写的数字会直接记为本月的「工资」收入，并参与未分配计算；留空则保持已有记录不变。")
                }
                Section {
                    ForEach(allocatable) { category in
                        allocationRow(category)
                    }
                } header: {
                    Text("为各分区分配本月预算（\(month.title)）")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本月收入 \(Money(cents: effectiveIncomeCents).displayText) · 已分配 \(Money(cents: totalAllocatedCents).displayText)")
                        Text(
                            unallocatedCents >= 0
                                ? "剩余待分配 \(Money(cents: unallocatedCents).displayText)"
                                : "超出收入 \(Money(cents: -unallocatedCents).displayText)"
                        )
                        .foregroundStyle(unallocatedCents >= 0 ? Color.green : Color.red)
                        Text("未分配的金额不会被任何分区扣减，可以稍后再分配。")
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
        if let salary = salaryIncome {
            incomeString = Money(cents: salary.cents).inputText
        }
    }

    private func save() {
        let transactionService = TransactionService(context: context)
        let allocationService = BudgetService(context: context)
        do {
            // 收入模块：填写的数字直接记为本月「工资」收入
            let incomeCents = Money(string: incomeString)?.cents ?? salaryIncomeCents
            if incomeCents > 0 {
                if let existing = salaryIncome {
                    try transactionService.update(existing, cents: incomeCents, description: "工资")
                } else {
                    try transactionService.addIncome(cents: incomeCents, description: "工资", date: Date())
                }
            }
            for category in allocatable {
                let cents = Money(string: amounts[category.categoryID] ?? "")?.cents ?? 0
                try allocationService.setInitialAllocation(
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
