import CryptoKit
import Foundation
import SwiftData

struct CaptureInboxService {
    enum EnqueueResult: Equatable {
        case insertedRecognized(UUID)
        case insertedNeedsReview(UUID)
        case duplicate
    }

    let context: ModelContext

    @discardableResult
    func enqueue(text: String, source: String = "银行短信") throws -> EnqueueResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = normalized.isEmpty
            ? "快捷指令没有传入短信正文。请把“短信正文”设置为“快捷指令输入”的“正文”。"
            : normalized

        let fingerprint = Self.fingerprint(for: payload)
        let existing = try context.fetch(FetchDescriptor<CaptureInboxItem>())
        guard !existing.contains(where: { $0.fingerprint == fingerprint }) else {
            return .duplicate
        }

        let parsed = normalized.isEmpty ? nil : CaptureParser.parseBankSMS(normalized)
        let item = CaptureInboxItem(
            fingerprint: fingerprint,
            parsed: parsed,
            rawText: payload,
            source: source
        )
        context.insert(item)
        try context.save()
        return parsed == nil
            ? .insertedNeedsReview(item.captureID)
            : .insertedRecognized(item.captureID)
    }

    func markRecorded(_ item: CaptureInboxItem) throws {
        item.state = .recorded
        item.processedAt = Date()
        // 处理完成后不再长期保留完整短信正文，只保留摘要和去重指纹。
        item.rawText = ""
        try context.save()
    }

    func discard(_ item: CaptureInboxItem) throws {
        item.state = .discarded
        item.processedAt = Date()
        item.rawText = ""
        try context.save()
    }

    static func fingerprint(for text: String) -> String {
        let compact = text
            .lowercased()
            .filter { !$0.isWhitespace }
        let digest = SHA256.hash(data: Data(compact.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
