import SwiftUI
import SwiftData

/// 共用的记录行。
struct TransactionRowView: View {
    let transaction: Transaction
    let categories: [BudgetCategory]
    var accounts: [Account] = []
    var onTap: (() -> Void)? = nil

    private var category: BudgetCategory? {
        categories.first { $0.categoryID == transaction.categoryID }
    }

    private var accountName: String? {
        guard let id = transaction.accountID else { return nil }
        return accounts.first { $0.accountID == id }?.name
    }

    private var displayTitle: String {
        let text = transaction.title.isEmpty ? transaction.merchant : transaction.title
        return text.isEmpty ? "未命名记录" : text
    }

    private var categoryLabel: String {
        if let category { return category.name }
        return transaction.type == .income ? "收入" : "未分类"
    }

    private var amountText: String {
        let money = Money(cents: transaction.cents).displayText
        return transaction.type == .expense ? "-\(money)" : "+\(money)"
    }

    var body: some View {
        HStack(spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.body)
                HStack(spacing: 4) {
                    Text(categoryLabel)
                    if let accountName {
                        Text("·")
                        Text(accountName)
                    }
                    Text("·")
                    Text(AppFormat.transactionDateText(transaction.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(amountText)
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.type == .expense ? Color.red : Color.green)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    @ViewBuilder
    private var iconView: some View {
        if let category {
            ZStack {
                Circle()
                    .fill(Color(hex: category.colorHex).opacity(0.15))
                Image(systemName: category.icon)
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: category.colorHex))
            }
            .frame(width: 40, height: 40)
        } else {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                Image(systemName: transaction.type == .income ? "plus.circle" : "questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
        }
    }
}
