import Foundation

/// 金额值类型：内部一律以「分」（Int64）存储与运算，避免浮点误差（规格第二十六节）。
/// 展示时再转换为「元」的文本。
struct Money: Hashable, Comparable, Codable, Sendable {
    let cents: Int64

    init(cents: Int64) {
        self.cents = cents
    }

    init(yuan: Int64) {
        self.cents = yuan * 100
    }

    /// 解析用户输入的「元」金额，如 "36" / "36.5" / "36.50"，四舍五入到分。
    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let scaled = NSDecimalNumber(decimal: value * Decimal(100)).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )
        guard scaled != NSDecimalNumber.notANumber else { return nil }
        self.cents = scaled.int64Value
    }

    static let zero = Money(cents: 0)

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }
    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }

    var isNegative: Bool { cents < 0 }

    /// 界面展示文本：¥36 / ¥1,234.56 / -¥48
    var displayText: String {
        let negative = cents < 0
        let total = abs(cents)
        let yuan = total / 100
        let fen = total % 100
        let grouped = Money.yuanGroupFormatter.string(from: NSNumber(value: yuan)) ?? "\(yuan)"
        let sign = negative ? "-" : ""
        if fen == 0 {
            return "\(sign)¥\(grouped)"
        }
        return "\(sign)¥\(grouped).\(fen < 10 ? "0" : "")\(fen)"
    }

    /// 输入框回填文本（无分组、无货币符号）：36 / 36.5 / 1234.56
    var inputText: String {
        let negative = cents < 0
        let total = abs(cents)
        let yuan = total / 100
        let fen = total % 100
        let sign = negative ? "-" : ""
        if fen == 0 {
            return "\(sign)\(yuan)"
        }
        return "\(sign)\(yuan).\(fen < 10 ? "0" : "")\(fen)"
    }

    private static let yuanGroupFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
