import SwiftUI
import Observation

enum AppTab: Hashable {
    case home
    case budget
    case transactions
    case settings
}

/// 跨 Tab 的轻量导航状态（例如首页「查看全部」跳到记录页）。
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
}
