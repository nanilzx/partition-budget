import Foundation

/// 一条「待确认入账」的预填数据：来自截图识别或银行短信识别。
struct CapturePrefill: Identifiable, Equatable {
    let id: UUID
    let amountCents: Int64
    let merchant: String
    let date: Date
    let source: String

    init(id: UUID = UUID(), amountCents: Int64, merchant: String, date: Date, source: String) {
        self.id = id
        self.amountCents = amountCents
        self.merchant = merchant
        self.date = date
        self.source = source
    }
}
