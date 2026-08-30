import CryptoKit
import Foundation
import SwiftData

struct CaptureInboxService {
    enum EnqueueResult: Equatable {
        case inserted(UUID)
        case duplicate
        case unrecognized
    }

    let context: ModelContext

    @discardableResult
    func enqueue(text: String, source: String = "银行短信") throws -> EnqueueResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let parsed = CaptureParser.parseBankSMS(normalized) else {
            return .unrecognized
        }

        let fingerprint = Self.fingerprint(for: normalized)
        let existing = try context.fetch(FetchDescriptor<CaptureInboxItem>())
        guard !existing.contains(where: { $0.fingerprint == fingerprint }) else {
            return .duplicate
        }

        let item = CaptureInboxItem(
            fingerprint: fingerprint,
            parsed: parsed,
            rawText: normalized,
            source: source
        )
        context.insert(item)
        try context.save()
        return .inserted(item.captureID)
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
