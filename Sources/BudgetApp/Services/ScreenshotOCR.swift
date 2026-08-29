import UIKit
import Vision

/// 截图识别：本机 Vision OCR + 解析（完全离线，不经过任何服务器）。
enum ScreenshotOCR {

    @discardableResult
    static func recognizePrefill(in image: UIImage) async -> CapturePrefill? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = downscaled(image, maxDimension: 1600).cgImage else { return nil }
            guard let lines = try? recognizeText(cgImage: cgImage) else { return nil }
            guard let parsed = CaptureParser.parsePaymentScreen(lines: lines) else { return nil }
            return CapturePrefill(
                amountCents: parsed.amountCents,
                merchant: parsed.merchant,
                date: parsed.date ?? Date(),
                source: parsed.source
            )
        }.value
    }

    static func recognizeText(cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
