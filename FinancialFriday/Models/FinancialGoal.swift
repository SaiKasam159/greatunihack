import Foundation
import SwiftData

@Model
final class FinancialGoal {
    var id: UUID
    var name: String
    var targetMinorUnits: Int64
    var deadline: Date
    var createdAt: Date

    init(id: UUID = UUID(), name: String, targetAmount: Decimal, deadline: Date, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.targetMinorUnits = NSDecimalNumber(decimal: targetAmount * 100).int64Value
        self.deadline = deadline
        self.createdAt = createdAt
    }

    var targetAmount: Decimal {
        get { Decimal(targetMinorUnits) / 100 }
        set { targetMinorUnits = NSDecimalNumber(decimal: newValue * 100).int64Value }
    }
}
