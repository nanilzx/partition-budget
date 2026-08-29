import Foundation
import Observation

/// 待确认入账的中心管道：截图识别 / 快捷指令识别的结果统一从这里弹出确认单。
/// 确认前不会动任何预算数据。
@MainActor
@Observable
final class CaptureIntake {
    static let shared = CaptureIntake()
    private init() {}

    var pending: CapturePrefill?

    /// 最近已入列的指纹，防止同一笔识别重复弹出。
    private var recentKeys: [String] = []

    func present(_ prefill: CapturePrefill) {
        let key = "\(prefill.amountCents)-\(prefill.merchant)-\(Int(prefill.date.timeIntervalSince1970 / 60))"
        guard !recentKeys.contains(key) else { return }
        recentKeys.append(key)
        if recentKeys.count > 30 {
            recentKeys.removeFirst()
        }
        pending = prefill
    }

    /// 快捷指令入口：银行短信等文本。
    func ingestText(_ text: String, source: String) {
        guard let parsed = CaptureParser.parseBankSMS(text) else { return }
        present(
            CapturePrefill(
                amountCents: parsed.amountCents,
                merchant: parsed.merchant,
                date: parsed.date ?? Date(),
                source: source
            )
        )
    }
}
