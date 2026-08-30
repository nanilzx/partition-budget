import Foundation

/// 银行交易短信解析（纯函数，配套单元测试）。
/// 解析失败返回 nil，由用户手动选择分区。
public enum CaptureParser {

    public enum TransactionKind: String, Codable, Equatable, Sendable {
        case expense
        case income
        case refund
    }

    public struct Parsed: Equatable {
        public let amountCents: Int64
        public let merchant: String
        public let date: Date?
        public let source: String
        public let transactionKind: TransactionKind
        public let bankName: String
        public let channel: String
        public let cardLastFour: String?
        public let confidence: Double

        public init(
            amountCents: Int64,
            merchant: String,
            date: Date?,
            source: String,
            transactionKind: TransactionKind,
            bankName: String,
            channel: String,
            cardLastFour: String?,
            confidence: Double
        ) {
            self.amountCents = amountCents
            self.merchant = merchant
            self.date = date
            self.source = source
            self.transactionKind = transactionKind
            self.bankName = bankName
            self.channel = channel
            self.cardLastFour = cardLastFour
            self.confidence = confidence
        }
    }

    private static let dateTimePattern = "([0-9]{4})[年./\\-]([0-9]{1,2})[月./\\-]([0-9]{1,2})日?\\s*([0-9]{1,2}):([0-9]{2})"
    private static let shortDateTimePattern = "([0-9]{1,2})月([0-9]{1,2})日\\s*([0-9]{1,2}):([0-9]{2})"

    private static let banks = [
        "工商银行", "建设银行", "农业银行", "中国银行", "招商银行", "交通银行", "邮储银行",
        "中信银行", "浦发银行", "民生银行", "兴业银行", "广发银行", "平安银行", "光大银行",
        "华夏银行", "北京银行", "上海银行",
    ]
    private static let channels = [
        "微信支付", "支付宝", "财付通", "云闪付", "银联", "美团", "京东", "滴滴", "抖音",
    ]
    private static let expenseIndicators = ["消费", "支付", "扣款", "扣费", "付款", "支出"]
    private static let incomeIndicators = ["收入", "入账", "转入", "存入", "工资"]
    private static let refundIndicators = ["退款", "退货", "冲正", "撤销"]

    // MARK: - 银行扣款短信

    public static func parseBankSMS(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Parsed? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.contains("元"),
              !normalized.contains("验证码"),
              !normalized.contains("动态密码"),
              !normalized.contains("还款"),
              let transactionKind = transactionKind(in: normalized),
              let amountCents = parseSMSAmount(normalized) else { return nil }

        let bank = banks.first { text.contains($0) } ?? ""
        let channel = channels.first { text.contains($0) } ?? ""
        let counterparty = extractCounterparty(from: normalized)
        let merchantDetail = counterparty.isEmpty ? channel : counterparty
        var merchant = [bank, merchantDetail].filter { !$0.isEmpty }.joined(separator: "·")
        if merchant.isEmpty { merchant = "快捷支付" }
        let date = parseDate(text: normalized, now: now, calendar: calendar)
        let confidence = bank.isEmpty ? 0.72 : (date == nil ? 0.82 : 0.92)
        return Parsed(
            amountCents: amountCents,
            merchant: merchant,
            date: date,
            source: "银行短信",
            transactionKind: transactionKind,
            bankName: bank,
            channel: channel,
            cardLastFour: extractCardLastFour(from: normalized),
            confidence: transactionKind == .refund ? min(confidence, 0.8) : confidence
        )
    }

    /// 短信里的第一个交易金额；跳过「尾号」「余额」前缀的数字（那是卡号与余额）。
    static func parseSMSAmount(_ text: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9][0-9,]*(?:\\.[0-9]{1,2})?)元") else { return nil }
        let nsText = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let context = nsText.substring(to: match.range.location)
            let window = String(context.suffix(10))
            if window.contains("余额")
                || window.contains("可用额度")
                || window.contains("尾号")
                || window.contains("应还") { continue }
            guard let groupRange = Range(match.range(at: 1), in: text) else { continue }
            if let cents = Money(string: sanitizedNumber(String(text[groupRange])))?.cents, cents > 0 {
                return cents
            }
        }
        return nil
    }

    static func transactionKind(in text: String) -> TransactionKind? {
        if refundIndicators.contains(where: text.contains) { return .refund }
        if incomeIndicators.contains(where: text.contains) { return .income }
        if expenseIndicators.contains(where: text.contains) { return .expense }
        return nil
    }

    static func extractCardLastFour(from text: String) -> String? {
        let patterns = [
            "(?:尾号|末四位)[^0-9]{0,3}([0-9]{4})",
            "卡号后四位[^0-9]{0,3}([0-9]{4})",
        ]
        for pattern in patterns {
            if let result = firstGroups(pattern: pattern, in: text, count: 1)?.first {
                return result
            }
        }
        return nil
    }

    static func extractCounterparty(from text: String) -> String {
        let patterns = [
            "(?:在|向)([^，。；,\\s]{2,24}?)(?:消费|支付|付款|扣款)",
            "商户[：:]?([^，。；,\\s]{2,24})",
        ]
        for pattern in patterns {
            guard let value = firstGroups(pattern: pattern, in: text, count: 1)?.first else {
                continue
            }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count >= 2 { return cleaned }
        }
        return ""
    }

    // MARK: - 工具

    static func sanitizedNumber(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
    }

    static func parseDate(text: String, now: Date, calendar: Calendar) -> Date? {
        if let groups = firstGroups(pattern: dateTimePattern, in: text, count: 5) {
            let comps = DateComponents(
                year: Int(groups[0]),
                month: Int(groups[1]),
                day: Int(groups[2]),
                hour: Int(groups[3]),
                minute: Int(groups[4])
            )
            return calendar.date(from: comps)
        }
        if let groups = firstGroups(pattern: shortDateTimePattern, in: text, count: 4) {
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = Int(groups[0])
            comps.day = Int(groups[1])
            comps.hour = Int(groups[2])
            comps.minute = Int(groups[3])
            if var date = calendar.date(from: comps) {
                // 元旦附近收到上一年 12 月短信时，不能误判成未来日期。
                if date > now.addingTimeInterval(86400) {
                    date = calendar.date(byAdding: .year, value: -1, to: date) ?? date
                }
                if date >= now.addingTimeInterval(-86400 * 180) {
                    return date
                }
            }
        }
        return nil
    }

    static func firstGroups(pattern: String, in text: String, count: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > count else { return nil }
        return (1...count).map { nsText.substring(with: match.range(at: $0)) }
    }
}
