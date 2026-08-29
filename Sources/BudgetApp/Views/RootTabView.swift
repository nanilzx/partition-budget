import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppTab.home)
            BudgetView()
                .tabItem { Label("预算", systemImage: "chart.pie.fill") }
                .tag(AppTab.budget)
            TransactionsView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)
            SettingsView()
                .tabItem { Label("我的", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task {
            // 首次启动写入默认分区；每次启动惰性生成当月预算（含结转）
            do {
                try SeedData.installDefaultCategoriesIfNeeded(context: context)
                try MonthlyBudgetService(context: context).ensureMonthlyBudget(for: .current)
            } catch {
                // 数据库异常时不阻塞 App 启动，界面呈现空状态
            }
        }
        .onOpenURL { url in
            // 分享扩展识别结果 → URL Scheme 通道
            CaptureIntake.shared.ingestURL(url)
        }
        .onChange(of: scenePhase) { _, phase in
            // 分享扩展识别结果 → 剪贴板兜底通道
            if phase == .active {
                CaptureIntake.shared.checkClipboard()
            }
        }
        .sheet(item: Binding(
            get: { CaptureIntake.shared.pending },
            set: { CaptureIntake.shared.pending = $0 }
        )) { prefill in
            AddTransactionSheet(capture: prefill)
        }
    }
}
