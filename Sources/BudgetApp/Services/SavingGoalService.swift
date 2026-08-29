import Foundation
import SwiftData

/// 储蓄目标管理（规格第十七节）。
struct SavingGoalService {
    let context: ModelContext

    @discardableResult
    func create(name: String, categoryID: UUID, targetCents: Int64, targetDate: Date?) throws -> SavingGoal {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServiceError.invalidName }
        guard targetCents > 0 else { throw ServiceError.invalidAmount }
        let goal = SavingGoal(name: trimmed, categoryID: categoryID, targetCents: targetCents, targetDate: targetDate)
        context.insert(goal)
        try context.save()
        return goal
    }

    func update(
        _ goal: SavingGoal,
        name: String? = nil,
        categoryID: UUID? = nil,
        targetCents: Int64? = nil,
        targetDate: Date?? = nil
    ) throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ServiceError.invalidName }
            goal.name = trimmed
        }
        if let categoryID { goal.categoryID = categoryID }
        if let targetCents {
            guard targetCents > 0 else { throw ServiceError.invalidAmount }
            goal.targetCents = targetCents
        }
        if let targetDate { goal.targetDate = targetDate }
        try context.save()
    }

    func delete(_ goal: SavingGoal) throws {
        context.delete(goal)
        try context.save()
    }
}
