import Foundation

struct MonthlyCashFlow: Identifiable, Sendable {
    let month: Date
    let income: Decimal
    let expenses: Decimal
    let isComplete: Bool
    var id: Date { month }
    var net: Decimal { income - expenses }
}

struct SpendingCategorySummary: Identifiable, Sendable {
    let category: String
    let amount: Decimal
    let percentage: Decimal
    let transactionCount: Int
    var id: String { category }
}

struct WeekdaySpending: Identifiable, Sendable {
    let weekday: Int
    let name: String
    let average: Decimal
    var id: Int { weekday }
}

struct SpendingInsight: Identifiable, Sendable {
    let id: String
    let icon: String
    let text: String
}

struct FinancialSummary: Sendable {
    let transactions: [Transaction]
    let openingBalance: Decimal
    let currentBalance: Decimal
    let totalIncome: Decimal
    let totalExpenses: Decimal
    let netCashFlow: Decimal
    let averageMonthlyIncome: Decimal
    let averageMonthlyExpenses: Decimal
    let averageMonthlyNetCashFlow: Decimal
    let averageWeeklySpending: Decimal
    let averageDailySpending: Decimal
    let firstTransactionDate: Date
    let referenceDate: Date
    let monthlyCashFlow: [MonthlyCashFlow]
    let categories: [SpendingCategorySummary]
    let weekdaySpending: [WeekdaySpending]
    let insights: [SpendingInsight]
    let highestSpendingMerchant: String?
    let largestExpense: Transaction?
}

struct GoalPlan: Sendable {
    enum Feasibility: String, Sendable {
        case comfortable = "Within historical surplus"
        case tight = "Above historical surplus"
        case unavailable = "No positive surplus history"
    }

    let daysRemaining: Int
    let monthlyContribution: Decimal
    let weeklyContribution: Decimal
    let feasibility: Feasibility
}
