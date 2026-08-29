import Foundation

/// 银行扣款短信解析（纯函数，配套单元测试）。
/// 解析失败返回 nil，由用户手动选择分区。
public enum CaptureParser {

    public struct Parsed: Equatable {
        public let amountCents: Int64
        public let merchant: String
        public let date: Date?
        public let source: String

        public init(amountCents: Int64, merchant: String, date: Date?, source: String) {
            self.amountCents = amountCents
            self.merchant = merchant
            self.date = date
            self.source = source
        }
    }

    private static let dateTimePattern = "([0-9]{4})[年./\\-]([0-9]{1,2})[月./\\-]([0-9]{1,2})日?\\s*([0-9]{1,2}):([0-9]{2})"
    private static let shortDateTimePattern = "([0-9]{1,2})月([0-9]{1,2})日\\s*([0-9]{1,2}):([0-9]{2})"

    private static let banks = [
        "工商银行", "建设银行", "农业银行", "中国银行", "招商银行", "交通银行", "邮储银行",
        "中信银行", "浦发银行", "民生银行", "兴业银行", "广发银行", "平安银行", "光大银行",
        "华夏银行", "北京银行", "上海银行",
    ]
    private static let channels = ["支付宝", "微信", "财付通", "云闪付", "银联", "美团", "京东", "滴滴"]

    // MARK: - 银行扣款短信

    public static func parseBankSMS(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Parsed? {
        guard text.contains("元"), let amountCents = parseSMSAmount(text) else { return nil }
        let bank = banks.first { text.contains($0) } ?? ""
        let channel = channels.first { text.contains($0) } ?? ""
        var merchant = [bank, channel].filter { !$0.isEmpty }.joined(separator: "·")
        if merchant.isEmpty { merchant = "快捷支付" }
        let date = parseDate(text: text, now: now, calendar: calendar)
        return Parsed(amountCents: amountCents, merchant: merchant, date: date, source: "银行短信")
    }

    /// 短信里的第一个交易金额；跳过「尾号」「余额」前缀的数字（那是卡号与余额）。
    static func parseSMSAmount(_ text: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9][0-9,]*(?:\\.[0-9]{1,2})?)元") else { return nil }
        let nsText = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let context = nsText.substring(to: match.range.location)
            let window = String(context.suffix(10))
            if window.contains("余额") || window.contains("尾号") { continue }
            guard let groupRange = Range(match.range(at: 1), in: text) else { continue }
            if let cents = Money(string: sanitizedNumber(String(text[groupRange])))?.cents, cents > 0 {
                return cents
            }
        }
        return nil
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
            if let date = calendar.date(from: comps),
               date <= now.addingTimeInterval(86400), date >= now.addingTimeInterval(-86400 * 180) {
                return date
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
