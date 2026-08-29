import Foundation

/// 识别结果在「分享面板扩展 / 快捷指令 → 主 App」之间传递的载体。
/// 编码为 base64url，通过 URL Scheme 或剪贴板兜底通道传回主 App。
public struct CapturePayload: Codable, Equatable {
    public let cents: Int64
    public let merchant: String
    public let timestamp: Date
    public let source: String

    public init(cents: Int64, merchant: String, timestamp: Date, source: String) {
        self.cents = cents
        self.merchant = merchant
        self.timestamp = timestamp
        self.source = source
    }

    /// 剪贴板兜底通道的内容前缀，主 App 只识别带此前缀的文本。
    public static let clipboardPrefix = "【分区预算】"

    /// partitionbudget://capture?d=<base64url>
    public func encodedDataURL() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return "partitionbudget://capture?d=" + data.base64URLEncodedString()
    }

    public static func decodeBase64(_ raw: String) -> CapturePayload? {
        var value = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 {
            value += "="
        }
        guard let data = Data(base64Encoded: value),
              let payload = try? JSONDecoder().decode(CapturePayload.self, from: data) else { return nil }
        return payload
    }

    public static func decodeClipboard(_ text: String) -> CapturePayload? {
        guard text.hasPrefix(clipboardPrefix) else { return nil }
        return decodeBase64(String(text.dropFirst(clipboardPrefix.count)))
    }
}

extension Data {
    /// URL 安全的 base64（无 +/= 字符，可直接放进 URL 查询参数）
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
