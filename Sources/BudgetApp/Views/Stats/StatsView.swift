import SwiftUI
import SwiftData
import Charts

/// 统计页（规格第十九节）：本月概览 + 每日支出柱状图 + 分区消费排行。
/// 图表风格克制：无背景框、单色柱、无 3D。
struct StatsView: View {
    var month: BudgetMonth = .current

    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BudgetCategory.sortOrder), SortDescriptor(\BudgetCategory.createdAt)])
    private var categories: [BudgetCategory]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    private var monthTransactions: [Transaction] {
        allTransactions.filter { $0.year == month.year && $0.month == month.month }
    }

    private var previousMonthTransactions: [Transaction] {
        let previous = month.previous
        return allTransactions.filter { $0.year == previous.year && $0.month == previous.month }
    }

    private var monthExpenseCents: Int64 { StatsCalculator.expenseCents(transactions: monthTransactions) }
    private var monthIncomeCents: Int64 { StatsCalculator.incomeCents(transactions: monthTransactions) }
    private var previousExpenseCents: Int64 { StatsCalculator.expenseCents(transactions: previousMonthTransactions) }

    private var elapsedDays: Int {
        guard month == BudgetMonth.current else {
            return StatsCalculator.daysInMonth(month)
        }
        let today = Calendar.current.component(.day, from: Date())
        let total = StatsCalculator.daysInMonth(month)
        return min(today, total)
    }

    private var dailyAverageCents: Int64 {
        StatsCalculator.dailyAverageCents(totalExpenseCents: monthExpenseCents, elapsedDays: elapsedDays)
    }

    private var largest: Transaction? { StatsCalculator.largestExpense(transactions: monthTransactions) }

    private var categoryTotals: [StatsCalculator.CategoryTotal] {
        StatsCalculator.totalsByCategory(transactions: monthTransactions, categories: categories)
    }

    private struct DailyPoint: Identifiable {
        let day: Int
        let cents: Int64
        var id: Int { day }
    }

    private var dailyData: [DailyPoint] {
        let daily = StatsCalculator.dailyExpenseCents(
            transactions: monthTransactions,
            year: month.year,
            month: month.month
        )
        let total = StatsCalculator.daysInMonth(month)
        return (1...total).map { DailyPoint(day: $0, cents: daily[$0] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                dailyChartSection
                categorySection
            }
            .dsGlassListSurface()
            .navigationTitle("统计 · \(month.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 子分区

    private var overviewSection: some View {
        Section {
            LabeledContent("\(month.month)月支出") {
                Text(Money(cents: monthExpenseCents).displayText)
                    .fontWeight(.semibold)
            }
            LabeledContent("\(month.month)月收入") {
                Text(Money(cents: monthIncomeCents).displayText)
                    .foregroundStyle(.green)
            }
            LabeledContent("结余") {
                Text(Money(cents: monthIncomeCents - monthExpenseCents).displayText)
                    .foregroundStyle(monthIncomeCents - monthExpenseCents < 0 ? Color.red : Color.primary)
            }
            LabeledContent("日均支出") {
                Text(Money(cents: dailyAverageCents).displayText)
            }
            if let largest {
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("最大单笔") {
                        Text(Money(cents: largest.cents).displayText)
                    }
                    Text("\(largest.title.isEmpty ? "未命名" : largest.title) · \(AppFormat.transactionDateText(largest.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if previousExpenseCents > 0 {
                LabeledContent("较上月") {
                    let delta = monthExpenseCents - previousExpenseCents
                    Text(
                        (delta >= 0 ? "+" : "") + Money(cents: delta).displayText
                    )
                    .foregroundStyle(delta > 0 ? Color.red : Color.green)
                }
            }
        } header: {
            Text("\(month.title)概览")
        }
        .dsGlassRowCard()
    }

    private var dailyChartSection: some View {
        Section {
            Chart(dailyData) { point in
                BarMark(
                    x: .value("日", point.day),
                    y: .value("支出", Double(point.cents) / 100)
                )
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5))
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .frame(height: 180)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("每日支出（元）")
        }
    }

    private var categorySection: some View {
        let total = categoryTotals.reduce(Int64(0)) { $0 + $1.cents }
        return Section {
            if categoryTotals.isEmpty {
                Text("本月还没有分区消费")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(categoryTotals) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let category = categories.first(where: { $0.categoryID == item.categoryID }) {
                            Image(systemName: category.icon)
                                .font(.caption)
                                .foregroundStyle(Color(hex: category.colorHex))
                        }
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(Money(cents: item.cents).displayText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(total > 0 ? "\(Int((Double(item.cents) / Double(total) * 100).rounded()))%" : "0%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.quaternarySystemFill))
                            Capsule()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: proxy.size.width * (total > 0 ? Double(item.cents) / Double(total) : 0))
                        }
                    }
                    .frame(height: DS.barHeight)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("分区消费排行")
        }
        .dsGlassRowCard()
    }
}
