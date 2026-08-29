import Foundation
import Observation
import UIKit

/// 待确认入账的中心管道：
/// - 分享扩展通过 URL Scheme / 剪贴板兜底把识别结果送进来
/// - 快捷指令（银行短信自动化）把文本送进来
/// 主 App 监听 pending，弹出预填好的记账单让用户确认。
@MainActor
@Observable
final class CaptureIntake {
    static let shared = CaptureIntake()
    private init() {}

    var pending: CapturePrefill?

    /// 最近已入列的指纹，防止同一笔识别重复弹出。
    private var recentKeys: [String] = []

    func ingestURL(_ url: URL) {
        guard url.scheme == "partitionbudget" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let payload = CapturePayload.decodeBase64(value) else { return }
        ingest(payload: payload)
    }

    func ingestClipboardText(_ text: String) {
        guard let payload = CapturePayload.decodeClipboard(text) else { return }
        UIPasteboard.general.string = ""
        ingest(payload: payload)
    }

    /// 快捷指令入口：银行短信等文本。
    func ingestText(_ text: String, source: String) {
        guard let parsed = CaptureParser.parseBankSMS(text) else { return }
        ingest(
            prefill: CapturePrefill(
                amountCents: parsed.amountCents,
                merchant: parsed.merchant,
                date: parsed.date ?? Date(),
                source: source
            )
        )
    }

    /// App 回到前台时检查剪贴板兜底通道（只认带专属前缀的内容，识别后立即清空）。
    func checkClipboard() {
        guard pending == nil,
              let text = UIPasteboard.general.string,
              text.hasPrefix(CapturePayload.clipboardPrefix) else { return }
        UIPasteboard.general.string = ""
        if let payload = CapturePayload.decodeClipboard(text) {
            ingest(payload: payload)
        }
    }

    private func ingest(payload: CapturePayload) {
        ingest(prefill: CapturePrefill(payload: payload))
    }

    private func ingest(prefill: CapturePrefill) {
        let key = "\(prefill.amountCents)-\(prefill.merchant)-\(Int(prefill.date.timeIntervalSince1970 / 60))"
        guard !recentKeys.contains(key) else { return }
        recentKeys.append(key)
        if recentKeys.count > 30 {
            recentKeys.removeFirst()
        }
        pending = prefill
    }
}
