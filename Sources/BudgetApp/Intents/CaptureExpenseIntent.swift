import AppIntents
import Foundation

/// 供 iOS「快捷指令」调用的入口：
/// 配合「收到银行短信时运行」自动化，把短信内容交给 App 解析并弹出记账确认。
/// 在快捷指令 App 里选择本指令，并把「信息内容」设为参数即可。
struct CaptureExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "识别消费（分区预算）"
    static let description = IntentDescription(
        "把银行短信或账单文本交给分区预算，自动识别金额并弹出记账确认。"
    )

    static var openAppWhenRun: Bool { true }

    @Parameter(title: "文本内容", requestValueDialog: "请提供要识别的短信或账单文本")
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别消费：\(\.$content)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureIntake.shared.ingestText(content, source: "快捷指令")
        return .result()
    }
}

/// 把识别动作注册到「快捷指令」App 的分区预算动作列表，并提供可直接搜索的快捷指令。
struct PartitionBudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureExpenseIntent(),
            phrases: [
                "用 \(.applicationName) 识别消费",
                "在 \(.applicationName) 中记一笔",
            ],
            shortTitle: "识别消费",
            systemImageName: "text.viewfinder"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .orange }
}
