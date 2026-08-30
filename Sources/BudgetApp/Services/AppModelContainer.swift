import SwiftData

/// 主 App 与后台 App Intent 共用同一份 SwiftData 容器。
@MainActor
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            BudgetCategory.self,
            Transaction.self,
            MonthlyBudget.self,
            MonthlyBudgetItem.self,
            BudgetTransfer.self,
            BudgetAdjustment.self,
            ClassificationRule.self,
            Account.self,
            SavingGoal.self,
            CaptureInboxItem.self,
        ])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration()])
        } catch {
            fatalError("无法初始化本地数据库：\(error)")
        }
    }()
}
