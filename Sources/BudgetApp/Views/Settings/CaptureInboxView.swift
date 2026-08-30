import SwiftData
import SwiftUI

/// 银行短信由快捷指令在后台写入这里；用户确认后才进入正式账本。
struct CaptureInboxView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<CaptureInboxItem> { $0.stateRaw == "pending" },
        sort: [SortDescriptor(\CaptureInboxItem.createdAt, order: .reverse)]
    )
    private var pendingItems: [CaptureInboxItem]

    @State private var selectedItem: CaptureInboxItem?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if pendingItems.isEmpty {
                ContentUnavailableView(
                    "没有待确认消费",
                    systemImage: "checkmark.circle",
                    description: Text("银行短信识别结果会先保存在这里，确认后才会计入预算。")
                )
            } else {
                List {
                    Section {
                        ForEach(pendingItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                inboxRow(item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    discard(item)
                                } label: {
                                    Label("忽略", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("左滑可以忽略误识别内容；系统会保留匿名去重指纹，避免同一短信再次出现。")
                    }
                }
            }
        }
        .navigationTitle("短信待确认")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            AddTransactionSheet(
                capture: item.prefill,
                onSaved: { markRecorded(item) }
            )
        }
        .alert(
            "操作失败",
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

    private func inboxRow(_ item: CaptureInboxItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: inboxIcon(for: item))
                .font(.title2)
                .foregroundStyle(inboxColor(for: item))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.merchant)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Group {
                    if item.isRecognized {
                        HStack(spacing: 6) {
                            Text(item.transactionKind.title)
                            if !item.cardLastFour.isEmpty {
                                Text("尾号 \(item.cardLastFour)")
                            }
                            Text(item.transactionDate, format: .dateTime.month().day().hour().minute())
                        }
                    } else {
                        Text(item.recognitionMessage)
                    }
                }
                .font(.caption)
                .foregroundStyle(item.isRecognized ? Color.secondary : Color.orange)
            }
            Spacer()
            Text(item.isRecognized ? Money(cents: item.amountCents).displayText : "待填写")
                .font(.headline.monospacedDigit())
                .foregroundStyle(item.isRecognized ? Color.primary : Color.orange)
        }
        .contentShape(Rectangle())
    }

    private func inboxIcon(for item: CaptureInboxItem) -> String {
        if !item.isRecognized { return "questionmark.circle.fill" }
        return item.transactionKind == .expense ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    private func inboxColor(for item: CaptureInboxItem) -> Color {
        if !item.isRecognized { return .orange }
        return item.transactionKind == .expense ? .red : .green
    }

    private func markRecorded(_ item: CaptureInboxItem) {
        do {
            try CaptureInboxService(context: context).markRecorded(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard(_ item: CaptureInboxItem) {
        do {
            try CaptureInboxService(context: context).discard(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension CaptureParser.TransactionKind {
    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .refund: return "退款"
        }
    }
}
