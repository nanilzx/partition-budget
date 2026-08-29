import SwiftUI

/// 首页顶部汇总卡：突出「本月还可以花」。
struct OverviewHeaderView: View {
    let summary: HomeSummary
    var onAllocateTapped: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月还可以花")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money(cents: summary.remainingCents).displayText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(summary.remainingCents < 0 ? Color.red : Color.primary)
            HStack(alignment: .top, spacing: 20) {
                stat("本月预算", summary.totalBudgetCents)
                stat("已使用", summary.spentCents)
                Button {
                    onAllocateTapped()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未分配")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money(cents: summary.unallocatedCents).displayText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(summary.unallocatedCents < 0 ? Color.red : Color.primary)
                        Text("去分配 >")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ title: String, _ cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Money(cents: cents).displayText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cents < 0 ? Color.red : Color.primary)
        }
    }
}
