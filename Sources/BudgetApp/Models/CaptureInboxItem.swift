import Foundation
import SwiftData

enum CaptureInboxState: String, Codable, Equatable, Sendable {
    case pending
    case recorded
    case discarded
}

/// 快捷指令在后台收到的银行短信。
/// 先持久化、后确认，避免 App 尚未打开或被系统终止时丢失识别结果。
@Model
final class CaptureInboxItem {
    var captureID: UUID = UUID()
    @Attribute(.unique)
    var fingerprint: String = ""
    var amountCents: Int64 = 0
    var merchant: String = ""
    var transactionKindRaw: String = CaptureParser.TransactionKind.expense.rawValue
    var transactionDate: Date = Date()
    var bankName: String = ""
    var channel: String = ""
    var cardLastFour: String = ""
    var rawText: String = ""
    var source: String = "银行短信"
    var confidence: Double = 0
    var isRecognized: Bool = true
    var recognitionMessage: String = ""
    var stateRaw: String = CaptureInboxState.pending.rawValue
    var createdAt: Date = Date()
    var processedAt: Date? = nil

    var state: CaptureInboxState {
        get { CaptureInboxState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var transactionKind: CaptureParser.TransactionKind {
        get { CaptureParser.TransactionKind(rawValue: transactionKindRaw) ?? .expense }
        set { transactionKindRaw = newValue.rawValue }
    }

    var prefill: CapturePrefill {
        CapturePrefill(
            id: captureID,
            amountCents: amountCents,
            merchant: merchant,
            date: transactionDate,
            source: source,
            transactionType: transactionKind == .expense ? .expense : .income,
            rawText: rawText
        )
    }

    init(
        fingerprint: String,
        parsed: CaptureParser.Parsed?,
        rawText: String,
        source: String
    ) {
        captureID = UUID()
        self.fingerprint = fingerprint
        self.rawText = rawText
        self.source = source
        if let parsed {
            amountCents = parsed.amountCents
            merchant = parsed.merchant
            transactionKindRaw = parsed.transactionKind.rawValue
            transactionDate = parsed.date ?? Date()
            bankName = parsed.bankName
            channel = parsed.channel
            cardLastFour = parsed.cardLastFour ?? ""
            confidence = parsed.confidence
            isRecognized = true
        } else {
            amountCents = 0
            merchant = "未识别的银行短信"
            transactionKindRaw = CaptureParser.TransactionKind.expense.rawValue
            transactionDate = Date()
            confidence = 0
            isRecognized = false
            recognitionMessage = rawText.contains("没有传入短信正文")
                ? "快捷指令未传入短信正文"
                : "已收到输入，但未识别出交易金额或类型"
        }
        stateRaw = CaptureInboxState.pending.rawValue
        createdAt = Date()
    }
}
