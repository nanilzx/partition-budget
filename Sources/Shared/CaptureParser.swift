import Foundation

/// 从「付款成功截图的 OCR 文本行」或「银行扣款短信」解析消费要素。
/// 全部为纯函数，主 App 与分享扩展共用，配套单元测试；解析失败返回 nil，由用户手动填写。
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

    // MARK: - 付款成功截图

    private static let amountKeywords = ["付款金额", "支付金额", "实付款", "实付", "金额", "合计"]
    private static let merchantKeywords = ["收款方", "收款商户", "商家", "商户名称", "付款对象"]
    private static let currencyPattern = "[¥￥]\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
    private static let dateTimePattern = "([0-9]{4})[年./\\-]([0-9]{1,2})[月./\\-]([0-9]{1,2})日?\\s*([0-9]{1,2}):([0-9]{2})"
    private static let shortDateTimePattern = "([0-9]{1,2})月([0-9]{1,2})日\\s*([0-9]{1,2}):([0-9]{2})"

    public static func parsePaymentScreen(
        lines: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Parsed? {
        let trimmed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty, let amountCents = parseAmount(lines: trimmed) else { return nil }
        let merchant = parseMerchant(lines: trimmed)
        let date = parseDate(text: trimmed.joined(separator: "\n"), now: now, calendar: calendar)
        return Parsed(amountCents: amountCents, merchant: merchant, date: date, source: "截图识别")
    }

    /// 金额：优先取带关键词（付款金额 ¥xx）的行；否则收集全部 ¥ 金额，唯一取它、多个取最大。
    static func parseAmount(lines: [String]) -> Int64? {
        for line in lines {
            let hasKeyword = amountKeywords.contains { line.contains($0) }
            guard hasKeyword,
                  let group = firstGroup(pattern: currencyPattern, in: line),
                  let cents = Money(string: sanitizedNumber(group))?.cents,
                  cents > 0 else { continue }
            return cents
        }
        let all = lines.compactMap { line -> Int64? in
            guard let group = firstGroup(pattern: currencyPattern, in: line) else { return nil }
            return Money(string: sanitizedNumber(group))?.cents
        }.filter { $0 > 0 }
        if all.isEmpty { return nil }
        if all.count == 1 { return all[0] }
        return all.max()
    }

    /// 商家：「收款方：某某」同行取冒号后；「收款方\n某某」取下一行；或「向某某付款」取中间。
    static func parseMerchant(lines: [String]) -> String {
        for (index, line) in lines.enumerated() {
            guard let key = merchantKeywords.first(where: { line.contains($0) }) else { continue }
            var candidate = ""
            if let range = line.range(of: key) {
                candidate = String(line[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "：: "))
            }
            if candidate.isEmpty, index + 1 < lines.count {
                candidate = lines[index + 1]
            }
            candidate = cleanMerchant(candidate)
            if !candidate.isEmpty { return candidate }
        }
        for line in lines {
            guard line.hasPrefix("向"), line.hasSuffix("付款"), line.count > 4 else { continue }
            let candidate = cleanMerchant(String(line.dropFirst().dropLast(2)))
            if !candidate.isEmpty { return candidate }
        }
        return ""
    }

    private static func cleanMerchant(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["的付款", "的收款"] where value.hasSuffix(suffix) && value.count > suffix.count {
            value = String(value.dropLast(suffix.count))
        }
        guard value.count >= 2, value.count <= 40 else { return "" }
        if value.contains("¥") || value.contains("￥") { return "" }
        if value.contains("成功") || value.contains("余额") || value.contains("付款方式") { return "" }
        return value
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

    // MARK: - 银行扣款短信

    private static let banks = [
        "工商银行", "建设银行", "农业银行", "中国银行", "招商银行", "交通银行", "邮储银行",
        "中信银行", "浦发银行", "民生银行", "兴业银行", "广发银行", "平安银行", "光大银行",
        "华夏银行", "北京银行", "上海银行",
    ]
    private static let channels = ["支付宝", "微信", "财付通", "云闪付", "银联", "美团", "京东", "滴滴"]

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

    static func firstGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }

    static func firstGroups(pattern: String, in text: String, count: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > count else { return nil }
        return (1...count).map { nsText.substring(with: match.range(at: $0)) }
    }
}
