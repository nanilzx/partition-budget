import SwiftUI
import SwiftData

@main
struct PartitionBudgetApp: App {
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                BudgetCategory.self,
                Transaction.self,
                MonthlyBudget.self,
                MonthlyBudgetItem.self,
                BudgetTransfer.self,
                BudgetAdjustment.self,
                ClassificationRule.self,
                Account.self,
            ])
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration()])
        } catch {
            fatalError("无法初始化本地数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppRouter())
        }
        .modelContainer(container)
    }
}
