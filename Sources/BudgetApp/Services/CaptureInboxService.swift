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
        let results = try enqueueAll(text: text, source: source)
        return results.first ?? .duplicate
    }

    /// 一次调用可以接收一条或多条短信；所有新记录在同一次保存中写入，避免只落下一半。
    @discardableResult
    func enqueueAll(text: String, source: String = "银行短信") throws -> [EnqueueResult] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloads = normalized.isEmpty
            ? ["快捷指令没有传入短信正文。请把“短信正文”设置为“快捷指令输入”的“正文”。"]
            : CaptureParser.splitBankSMSPayload(normalized)
        let existing = try context.fetch(FetchDescriptor<CaptureInboxItem>())
        var knownFingerprints = Set(existing.map(\.fingerprint))
        var results: [EnqueueResult] = []
        var insertedAny = false

        for payload in payloads {
            let fingerprint = Self.fingerprint(for: payload)
            guard knownFingerprints.insert(fingerprint).inserted else {
                results.append(.duplicate)
                continue
            }

            let parsed = normalized.isEmpty ? nil : CaptureParser.parseBankSMS(payload)
            let item = CaptureInboxItem(
                fingerprint: fingerprint,
                parsed: parsed,
                rawText: payload,
                source: source
            )
            context.insert(item)
            insertedAny = true
            results.append(
                parsed == nil
                    ? .insertedNeedsReview(item.captureID)
                    : .insertedRecognized(item.captureID)
            )
        }

        if insertedAny { try context.save() }
        return results
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
