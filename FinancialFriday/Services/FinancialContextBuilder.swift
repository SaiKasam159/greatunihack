import Foundation

@MainActor
enum FinancialContextBuilder {
    static func make(summary: FinancialSummary, goals: [FinancialGoal], referenceDate: Date = .now) -> String {
        let recentMonths = summary.monthlyCashFlow.suffix(6).map { month in
            let completeness = month.isComplete ? "complete" : "partial"
            return "- \(month.month.formatted(.dateTime.month(.abbreviated).year())) (\(completeness)): income \(AppFormatting.currency(month.income)), expenses \(AppFormatting.currency(month.expenses)), net \(AppFormatting.currency(month.net))"
        }.joined(separator: "\n")

        let categories = summary.categories.prefix(8).map { category in
            "- \(category.category): \(AppFormatting.currency(category.amount)) (\(formatPercent(category.percentage))% of expenses, \(category.transactionCount) transactions)"
        }.joined(separator: "\n")

        let weekdays = summary.weekdaySpending.map { day in
            "\(day.name) \(AppFormatting.currency(day.average))"
        }.joined(separator: ", ")

        let goalsText: String
        if goals.isEmpty {
            goalsText = "- No financial goals have been created."
        } else {
            goalsText = goals.map { goal in
                let plan = GoalCalculationService.plan(
                    target: goal.targetAmount,
                    deadline: goal.deadline,
                    historicalMonthlyNet: summary.averageMonthlyNetCashFlow,
                    from: referenceDate
                )
                let required = plan.map { ", required monthly contribution \(AppFormatting.currency($0.monthlyContribution))" } ?? ", deadline has passed"
                return "- \(goal.name): target \(AppFormatting.currency(goal.targetAmount)), deadline \(goal.deadline.formatted(date: .long, time: .omitted))\(required)"
            }.joined(separator: "\n")
        }

        return """
        FINANCIAL CONTEXT — HISTORICAL, NOT LIVE BANKING DATA
        Dataset period: \(summary.firstTransactionDate.formatted(date: .long, time: .omitted)) to \(summary.referenceDate.formatted(date: .long, time: .omitted)).
        Fixed opening balance: \(AppFormatting.currency(summary.openingBalance)).
        Calculated historical balance as of the final transaction: \(AppFormatting.currency(summary.currentBalance)).
        Total income: \(AppFormatting.currency(summary.totalIncome)).
        Total expenses: \(AppFormatting.currency(summary.totalExpenses)).
        Net cash flow: \(AppFormatting.currency(summary.netCashFlow)).
        Average complete-month income: \(AppFormatting.currency(summary.averageMonthlyIncome)).
        Average complete-month expenses: \(AppFormatting.currency(summary.averageMonthlyExpenses)).
        Average complete-month net cash flow: \(AppFormatting.currency(summary.averageMonthlyNetCashFlow)).
        Average weekly spending: \(AppFormatting.currency(summary.averageWeeklySpending)).
        Average daily spending: \(AppFormatting.currency(summary.averageDailySpending)).
        Highest-spend merchant: \(summary.highestSpendingMerchant ?? "Unavailable").
        Largest individual expense: \(largestExpenseDescription(summary.largestExpense)).

        RECENT MONTHLY CASH FLOW
        \(recentMonths)

        TOP SPENDING CATEGORIES
        \(categories)

        AVERAGE SPENDING BY CALENDAR WEEKDAY
        \(weekdays)

        SAVINGS GOALS
        \(goalsText)
        """
    }

    private static func formatPercent(_ value: Decimal) -> String {
        value.doubleValue.formatted(.number.precision(.fractionLength(1)))
    }

    private static func largestExpenseDescription(_ transaction: Transaction?) -> String {
        guard let transaction else { return "Unavailable" }
        return "\(AppFormatting.currency(transaction.expenseAmount)) at \(transaction.merchant) on \(transaction.timestamp.formatted(date: .abbreviated, time: .omitted))"
    }
}
