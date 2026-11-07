import Foundation

enum SpendingPatternAnalysisService {
    static func makeInsights(
        categories: [SpendingCategorySummary],
        weekdaySpending: [WeekdaySpending],
        monthlyCashFlow: [MonthlyCashFlow],
        highestMerchant: String?,
        largestExpense: Transaction?
    ) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        if let highestDay = weekdaySpending.max(by: { $0.average < $1.average }) {
            let friday = weekdaySpending.first { $0.weekday == 6 }
            let text: String
            if highestDay.weekday == 6 {
                text = "Friday has your highest average spend at \(AppFormatting.currency(highestDay.average)) per observed Friday."
            } else if let friday {
                text = "\(highestDay.name) has your highest average spend at \(AppFormatting.currency(highestDay.average)); Friday averages \(AppFormatting.currency(friday.average))."
            } else {
                text = "\(highestDay.name) has your highest average spend at \(AppFormatting.currency(highestDay.average))."
            }
            insights.append(SpendingInsight(id: "weekday", icon: "calendar", text: text))
        }
        if let category = categories.first {
            insights.append(SpendingInsight(
                id: "category",
                icon: "chart.pie",
                text: "\(category.category) is your largest spending category at \(category.percentage.doubleValue.formatted(.number.precision(.fractionLength(1))))% of expenses."
            ))
        }
        if let latestComplete = monthlyCashFlow.last(where: \.isComplete) {
            let direction = latestComplete.net >= 0 ? "surplus" : "deficit"
            insights.append(SpendingInsight(
                id: "month",
                icon: latestComplete.net >= 0 ? "arrow.up.right" : "arrow.down.right",
                text: "Your latest complete month ended with a \(direction) of \(AppFormatting.currency(abs(latestComplete.net)))."
            ))
        }
        if let highestMerchant, let largestExpense {
            insights.append(SpendingInsight(
                id: "merchant",
                icon: "storefront",
                text: "\(highestMerchant) received the most spending overall; your largest single expense was \(AppFormatting.currency(largestExpense.expenseAmount)) at \(largestExpense.merchant)."
            ))
        }
        return Array(insights.prefix(4))
    }
}
