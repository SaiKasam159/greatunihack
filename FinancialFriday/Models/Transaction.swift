import Foundation

struct Transaction: Identifiable, Sendable {
    let id: Int
    let timestamp: Date
    let merchant: String
    let category: String
    let amount: Decimal
    let type: String
    let channel: String
    let userID: String

    var isIncome: Bool { type == "credit" && amount > 0 }
    var isExpense: Bool { type == "debit" && amount < 0 }
    var expenseAmount: Decimal { isExpense ? -amount : 0 }
}
