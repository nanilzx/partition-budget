import SwiftUI

/// 首页预算分区行（规格：第一层名称 / 第二层剩余 / 第三层已用÷总预算 / 第四层细进度条）。
/// 轻量、无阴影无边框，交由 List 提供背景与分隔。
struct BudgetCategoryRowView: View {
    let card: CategoryCardModel

    /// 进度条颜色：分类色作识别辅助；超支一律红、未分配灰。
    private var barColor: Color {
        switch card.status {
        case .overspent: return .red
        case .unallocated: return .gray
        default: return Color(hex: card.colorHex)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: card.icon)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: card.colorHex))
                    .frame(width: 24)
                Text(card.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if card.status == .overspent {
                    Text("已超支")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("还剩 \(card.percentOfRemaining)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(remainingText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(card.remainingCents < 0 ? Color.red : Color.primary)
                .contentTransition(.numericText())
            Text("已使用 \(Money(cents: card.spentCents).displayText) / \(Money(cents: card.budgetCents).displayText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            progressBar
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.25), value: card.usageRatio)
    }

    private var remainingText: String {
        card.remainingCents < 0
            ? "超支 \(Money(cents: -card.remainingCents).displayText)"
            : "剩余 " + Money(cents: card.remainingCents).displayText
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.quaternarySystemFill))
                Capsule()
                    .fill(barColor)
                    .frame(width: proxy.size.width * min(max(card.usageRatio, 0), 1))
            }
        }
        .frame(height: DS.barHeight)
    }
}

extension CategoryCardModel {
    /// 还剩的百分比（预算为 0 时返回 0%）。
    var percentOfRemaining: String {
        guard budgetCents > 0 else { return "0%" }
        let ratio = Double(max(remainingCents, 0)) / Double(budgetCents)
        return "\(Int((ratio * 100).rounded()))%"
    }
}
