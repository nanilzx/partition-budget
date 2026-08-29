import Foundation

enum AppFormat {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    /// 记录列表里的时间：今天 12:30 / 昨天 09:12 / 8月28日 21:05
    static func transactionDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 " + timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 " + timeFormatter.string(from: date)
        }
        return dayFormatter.string(from: date) + " " + timeFormatter.string(from: date)
    }
}
