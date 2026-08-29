import SwiftUI

/// 预算分区卡片：优先展示剩余金额，进度条展示使用比例。
struct BudgetCategoryCardView: View {
    let card: CategoryCardModel
    var onTap: () -> Void = {}

    private var statusColor: Color {
        switch card.status {
        case .normal: return .green
        case .notice: return .orange
        case .warning, .overspent: return .red
        case .unallocated: return .gray
        }
    }

    private var statusText: String {
        if card.status == .overspent {
            return "已超支 \(Money(cents: -card.remainingCents).displayText)"
        }
        if card.status == .unallocated {
            return card.status.caption
        }
        return "\(card.status.caption) · 已用 \(card.percentText)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: card.colorHex).opacity(0.15))
                        Image(systemName: card.icon)
                            .font(.subheadline)
                            .foregroundStyle(Color(hex: card.colorHex))
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("剩 " + Money(cents: card.remainingCents).displayText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(card.remainingCents < 0 ? Color.red : Color.primary)
                        Text("预算 " + Money(cents: card.budgetCents).displayText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                progressBar
                HStack {
                    Text("已花 " + Money(cents: card.spentCents).displayText)
                    Spacer()
                    Text("占比 \(card.percentText)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.15))
                Capsule()
                    .fill(statusColor)
                    .frame(width: proxy.size.width * min(max(card.usageRatio, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
