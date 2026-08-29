import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// 分享面板扩展：接收付款成功截图 → 本机 Vision OCR → 解析金额/商家/时间 → 传回主 App 确认。
/// 全程离线，不经过任何服务器。
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private var hosting: UIHostingController<ShareCaptureView>?
    private var parsedPayload: CapturePayload?
    private var openedApp = false

    override func viewDidLoad() {
        super.viewDidLoad()
        showView(status: "正在识别截图…", showActions: false)
        Task { @MainActor in
            await processInput()
        }
    }

    // MARK: - 识别流程

    private func processInput() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            update(status: "没有找到分享内容")
            return
        }
        let providers = items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty else {
            update(status: "没有找到图片。请分享付款成功的截图再试。")
            return
        }

        for provider in providers.prefix(5) {
            guard let image = await loadImage(provider) else { continue }
            let payload = await Self.recognizePayload(in: image)
            if let payload {
                parsedPayload = payload
                showResult(payload: payload)
                return
            }
        }
        update(status: "未能从截图识别出金额。\n可以先手动记一笔，或换一张「付款成功」页面再试。")
    }

    private static func recognizePayload(in image: UIImage) async -> CapturePayload? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = downscaled(image, maxDimension: 1600).cgImage else { return nil }
            guard let lines = try? recognizeText(cgImage: cgImage) else { return nil }
            guard let parsed = CaptureParser.parsePaymentScreen(lines: lines) else { return nil }
            return CapturePayload(
                cents: parsed.amountCents,
                merchant: parsed.merchant,
                timestamp: parsed.date ?? Date(),
                source: parsed.source
            )
        }.value
    }

    private static func recognizeText(cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func loadImage(_ provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                switch item {
                case let image as UIImage:
                    continuation.resume(returning: image)
                case let url as URL:
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                case let data as Data:
                    continuation.resume(returning: UIImage(data: data))
                case let cgImage as CGImage:
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - 回传主 App

    private func showResult(payload: CapturePayload) {
        // 剪贴板兜底：部分系统版本不允许分享面板直接打开宿主 App
        if let encoded = payload.encodedDataURL() {
            UIPasteboard.general.string = CapturePayload.clipboardPrefix + encoded
        }
        openApp()
        let summary = "识别到 " + Money(cents: payload.cents).displayText
            + (payload.merchant.isEmpty ? "" : " · " + payload.merchant)
        update(status: summary + "\n已打开分区预算，请在 App 里确认入账。", showActions: true)
    }

    private func openApp() {
        guard !openedApp, let payload = parsedPayload,
              let encoded = payload.encodedDataURL(), let url = URL(string: encoded) else { return }
        openedApp = true
        extensionContext?.open(url, completionHandler: nil)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    // MARK: - 界面

    private func showView(status: String, showActions: Bool) {
        let rootView = ShareCaptureView(
            status: status,
            showActions: showActions,
            onOpen: { [weak self] in self?.openApp() },
            onDone: { [weak self] in self?.finish() }
        )
        let host = UIHostingController(rootView: rootView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hosting = host
    }

    private func update(status: String, showActions: Bool? = nil) {
        guard let host = hosting else { return }
        host.rootView = ShareCaptureView(
            status: status,
            showActions: showActions ?? host.rootView.showActions,
            onOpen: { [weak self] in self?.openApp() },
            onDone: { [weak self] in self?.finish() }
        )
    }
}

/// 分享扩展的极简界面：状态 + 两个动作。
struct ShareCaptureView: View {
    var status: String
    var showActions: Bool
    var onOpen: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text("分区预算 · 截图识别")
                .font(.headline)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if showActions {
                VStack(spacing: 10) {
                    Button(action: onOpen) {
                        Text("打开 App 确认")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: onDone) {
                        Text("完成")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
            }
            Spacer()
        }
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }
}
