import UIKit
import SwiftUI

/// 统一设计令牌（刻意保持最小集，不做过度抽象）：
/// 圆角、间距沿用系统默认观感，只把反复出现的值收拢到这里。
enum DS {
    /// 自定义轻量卡片的圆角
    static let cornerRadius: CGFloat = 12
    /// 玻璃容器的圆角
    static let glassCornerRadius: CGFloat = 22
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

    /// Liquid Glass 风格选项（iOS 26+）。
    enum Glass {
        /// 静态玻璃：强调层级
        case regular
        /// 交互玻璃：带按压反馈
        case interactive
        /// 轻微染色玻璃：用于需要一点分类色强调的控件
        case tinted(Color)
    }
}

extension View {

    /// Liquid Glass（iOS 26+ 官方 API）；旧系统回退 .thinMaterial。
    /// 玻璃只用于导航/控件/浮层层级，内容列表不要整体套玻璃。
    @ViewBuilder
    func dsGlass(_ style: DS.Glass = .regular, in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .regular:
                self.glassEffect(in: shape)
            case .interactive:
                self.glassEffect(.regular.interactive(), in: shape)
            case .tinted(let color):
                self.glassEffect(.regular.tint(color), in: shape)
            }
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }

    /// 把相邻的多个玻璃元素放进同一容器，获得融合/分离的液态变形效果（iOS 26+）。
    @ViewBuilder
    func dsGlassContainer<Content: View>(
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }

    /// 主操作按钮：iOS 26 用玻璃突出样式，旧系统回退 borderedProminent。
    @ViewBuilder
    func dsProminentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// iOS 26：向下滚动时系统 Tab Bar 自动收起（Liquid Glass 行为）。
    @ViewBuilder
    func dsMinimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
