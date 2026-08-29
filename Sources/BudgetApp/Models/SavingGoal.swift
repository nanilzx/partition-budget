import Foundation
import SwiftData

/// 储蓄目标（规格第十七节）：挂在储蓄类分区上，进度由该分区的累积余额派生。
@Model
final class SavingGoal {
    var goalID: UUID = UUID()
    var name: String = ""
    var categoryID: UUID = UUID()
    var targetCents: Int64 = 0
    var targetDate: Date? = nil
    var createdAt: Date = Date()

    init(name: String, categoryID: UUID, targetCents: Int64, targetDate: Date? = nil) {
        self.goalID = UUID()
        self.name = name
        self.categoryID = categoryID
        self.targetCents = targetCents
        self.targetDate = targetDate
        self.createdAt = Date()
    }
}

extension SavingGoal {
    static func all(in context: ModelContext) throws -> [SavingGoal] {
        try context.fetch(
            FetchDescriptor<SavingGoal>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    static func byID(_ id: UUID, in context: ModelContext) throws -> SavingGoal? {
        try all(in: context).first { $0.goalID == id }
    }
}
