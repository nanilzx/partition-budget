import SwiftUI
import SwiftData

@main
struct PartitionBudgetApp: App {
    private let container = AppModelContainer.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppRouter())
        }
        .modelContainer(container)
    }
}
