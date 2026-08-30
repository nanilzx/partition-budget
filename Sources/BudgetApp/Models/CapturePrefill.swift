import Foundation

/// 一条由银行短信识别得到的「待确认入账」预填数据。
struct CapturePrefill: Identifiable, Equatable {
    let id: UUID
    let amountCents: Int64
    let merchant: String
    let date: Date
    let source: String
    let transactionType: TransactionType
    let rawText: String

    init(
        id: UUID = UUID(),
        amountCents: Int64,
        merchant: String,
        date: Date,
        source: String,
        transactionType: TransactionType = .expense,
        rawText: String = ""
    ) {
        self.id = id
        self.amountCents = amountCents
        self.merchant = merchant
        self.date = date
        self.source = source
        self.transactionType = transactionType
        self.rawText = rawText
    }
}
