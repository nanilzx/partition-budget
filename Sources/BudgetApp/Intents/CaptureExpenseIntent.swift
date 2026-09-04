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
        let results = try await enqueueWithRetry(text: content ?? "")
        let recognizedCount = results.filter {
            if case .insertedRecognized = $0 { return true }
            return false
        }.count
        let reviewCount = results.filter {
            if case .insertedNeedsReview = $0 { return true }
            return false
        }.count
        let insertedCount = recognizedCount + reviewCount

        if insertedCount > 1 {
            return .result(dialog: "已接收并保存 \(insertedCount) 条银行短信，其中 \(recognizedCount) 条已识别")
        } else if recognizedCount == 1 {
            return .result(dialog: "已识别并加入分区预算的待确认列表")
        } else if reviewCount == 1 {
            return .result(dialog: "已收到短信，但未完整识别；请在分区预算的待确认列表中检查")
        } else {
            return .result(dialog: "这条银行短信已经识别过，不会重复添加")
        }
    }

    /// 后台连续触发时持久化存储可能短暂繁忙；使用新 Context 退避重试，
    /// 已经成功写入的内容会在下一次尝试中被指纹识别为重复，不会产生两份。
    @MainActor
    private func enqueueWithRetry(text: String) async throws -> [CaptureInboxService.EnqueueResult] {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let context = ModelContext(AppModelContainer.shared)
                context.autosaveEnabled = false
                return try CaptureInboxService(context: context).enqueueAll(
                    text: text,
                    source: "快捷指令·银行短信"
                )
            } catch {
                lastError = error
                guard attempt < 3 else { break }
                try await Task.sleep(nanoseconds: UInt64(120_000_000 * (attempt + 1)))
            }
        }
        throw lastError ?? CancellationError()
    }
}
