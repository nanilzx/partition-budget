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

    /// List 分区中一行所处的位置。相邻行共享同一块玻璃时，内部边缘不能重复绘制。
    enum GlassRowPosition: Equatable {
        case single
        case first
        case middle
        case last

        init(index: Int, count: Int) {
            if count <= 1 {
                self = .single
            } else if index == 0 {
                self = .first
            } else if index == count - 1 {
                self = .last
            } else {
                self = .middle
            }
        }

        fileprivate var extendsAbove: Bool {
            self == .middle || self == .last
        }

        fileprivate var extendsBelow: Bool {
            self == .first || self == .middle
        }
    }
}

enum AppPreferences {
    static let fullGlassCardsEnabled = "fullGlassCardsEnabled"
}

private struct GlassRowCardModifier: ViewModifier {
    @AppStorage(AppPreferences.fullGlassCardsEnabled) private var isEnabled = false
    let position: DS.GlassRowPosition

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.listRowBackground(JoinedGlassRowBackground(position: position))
        } else {
            content
        }
    }
}

/// 把相邻 List 行的玻璃形状向内部接缝之外延伸，只显示整个分区的外轮廓。
/// 外边缘向内留 1pt，避免 Liquid Glass 的高光被 List 行裁剪掉。
private struct JoinedGlassRowBackground: View {
    let position: DS.GlassRowPosition

    var body: some View {
        GeometryReader { proxy in
            let extensionLength = DS.glassCornerRadius + 10
            let top = position.extendsAbove ? -extensionLength : 1
            let bottom = position.extendsBelow ? -extensionLength : 1
            let width = max(proxy.size.width - 2, 0)
            let height = max(proxy.size.height - top - bottom, 0)

            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: DS.glassCornerRadius)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.glassCornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: DS.glassCornerRadius)
                        .fill(.regularMaterial)
                }
            }
            .frame(width: width, height: height)
            .offset(x: 1, y: top)
        }
        .clipped()
    }
}

private struct GlassListSurfaceModifier: ViewModifier {
    @AppStorage(AppPreferences.fullGlassCardsEnabled) private var isEnabled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
        } else {
            content
        }
    }
}

extension View {

    /// Liquid Glass（iOS 26+ 官方 API）；旧系统回退 .thinMaterial。
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

    /// 列表分区的连续玻璃底色；根据行位置隐藏内部玻璃边缘，避免接缝双线。
    func dsGlassRowCard(position: DS.GlassRowPosition = .single) -> some View {
        modifier(GlassRowCardModifier(position: position))
    }

    /// 配套：隐藏 List 自带的实底背景，让玻璃材质有内容可透。
    func dsGlassListSurface() -> some View {
        modifier(GlassListSurfaceModifier())
    }
}
