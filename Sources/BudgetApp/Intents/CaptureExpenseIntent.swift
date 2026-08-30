import AppIntents
import Foundation
import SwiftData

/// 供 iOS「快捷指令」调用的入口：
/// 配合“收到银行短信时运行”自动化，把短信内容交给 App 在后台解析并持久化。
/// 在快捷指令 App 里选择本动作，并把“短信正文”设为收到的信息正文即可。
struct CaptureExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "接收银行短信正文"
    static let description = IntentDescription(
        "把银行短信交给分区预算，在后台识别并加入待确认列表。"
    )
    static var isDiscoverable: Bool { true }

    /// 短信自动化可以在后台完成收集；用户稍后在 App 的“待确认”中核对入账。
    static var openAppWhenRun: Bool { false }

    /// 使用可选参数，避免个人自动化忘记绑定变量时停下来询问用户。
    /// 空输入仍会写入一条可见诊断，告诉用户如何修正快捷指令。
    @Parameter(
        title: "短信正文",
        description: "由“收到信息”自动化传入的当次短信正文",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var content: String?

    static var parameterSummary: some ParameterSummary {
        Summary("接收银行短信：\(\.$content)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppModelContainer.shared)
        switch try CaptureInboxService(context: context).enqueue(
            text: content ?? "",
            source: "快捷指令·银行短信"
        ) {
        case .insertedRecognized(_):
            return .result(dialog: "已识别并加入分区预算的待确认列表")
        case .insertedNeedsReview(_):
            return .result(dialog: "已收到短信，但未完整识别；请在分区预算的待确认列表中检查")
        case .duplicate:
            return .result(dialog: "这条银行短信已经识别过，不会重复添加")
        }
    }
}
