import UIKit
import SwiftUI

/// 统一设计令牌（刻意保持最小集，不做过度抽象）：
/// 圆角、间距沿用系统默认观感，只把反复出现的值收拢到这里。
enum DS {
    /// 自定义轻量卡片的圆角
    static let cornerRadius: CGFloat = 12
    /// 页面水平留白
    static let padding: CGFloat = 16
    /// 细进度条高度
    static let barHeight: CGFloat = 4

    /// 克制的触感反馈：只在关键结果（成功/警告/删除）使用
    enum Haptic {
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        static func warning() {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        static func destructive() {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        static func tap() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
