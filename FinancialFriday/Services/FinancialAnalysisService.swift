import Foundation

enum FinancialAnalysisService {
    static func analyse(_ transactions: [Transaction]) -> FinancialSummary? {
        guard let firstDate = transactions.first?.timestamp,
              let referenceDate = transactions.last?.timestamp else { return nil }

        let incomeTransactions = transactions.filter(\.isIncome)
        let expenseTransactions = transactions.filter(\.isExpense)
        let income = incomeTransactions.reduce(Decimal.zero) { $0 + $1.amount }
        let expenses = expenseTransactions.reduce(Decimal.zero) { $0 + $1.expenseAmount }
        let net = transactions.reduce(Decimal.zero) { $0 + $1.amount }
        // The CSV has no account-opening-balance field, so balance figures reflect
        // only the net movement represented by the complete bundled dataset.
        let openingBalance = Decimal.zero
        let months = monthlyCashFlow(transactions, firstDate: firstDate, referenceDate: referenceDate)
        let completeMonths = months.filter(\.isComplete)
        let divisor = Decimal(max(completeMonths.count, 1))
        let averageIncome = completeMonths.reduce(Decimal.zero) { $0 + $1.income } / divisor
        let averageExpenses = completeMonths.reduce(Decimal.zero) { $0 + $1.expenses } / divisor

        let calendar = analysisCalendar
        let dayCount = max((calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: calendar.startOfDay(for: referenceDate)).day ?? 0) + 1, 1)
        let daily = expenses / Decimal(dayCount)
        let categories = categorySummaries(expenseTransactions, totalExpenses: expenses)
        let weekdayValues = weekdayAverages(expenseTransactions, firstDate: firstDate, referenceDate: referenceDate)

        let merchantTotals = Dictionary(grouping: expenseTransactions, by: \.merchant)
            .mapValues { $0.reduce(Decimal.zero) { $0 + $1.expenseAmount } }
        let highestMerchant = merchantTotals.max { $0.value < $1.value }?.key
        let largestExpense = expenseTransactions.max { $0.expenseAmount < $1.expenseAmount }
        let insights = SpendingPatternAnalysisService.makeInsights(
            categories: categories,
            weekdaySpending: weekdayValues,
            monthlyCashFlow: months,
            highestMerchant: highestMerchant,
            largestExpense: largestExpense
        )

        return FinancialSummary(
            transactions: transactions,
            openingBalance: openingBalance,
            currentBalance: openingBalance + net,
            totalIncome: income,
            totalExpenses: expenses,
            netCashFlow: net,
            averageMonthlyIncome: averageIncome,
            averageMonthlyExpenses: averageExpenses,
            averageMonthlyNetCashFlow: averageIncome - averageExpenses,
            averageWeeklySpending: daily * 7,
            averageDailySpending: daily,
            firstTransactionDate: firstDate,
            referenceDate: referenceDate,
            monthlyCashFlow: months,
            categories: categories,
            weekdaySpending: weekdayValues,
            insights: insights,
            highestSpendingMerchant: highestMerchant,
            largestExpense: largestExpense
        )
    }

    private static var analysisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return calendar
    }

    private static func monthlyCashFlow(_ transactions: [Transaction], firstDate: Date, referenceDate: Date) -> [MonthlyCashFlow] {
        let calendar = analysisCalendar
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.timestamp)) ?? transaction.timestamp
        }
        return grouped.map { month, values in
            let income = values.filter(\.isIncome).reduce(Decimal.zero) { $0 + $1.amount }
            let expenses = values.filter(\.isExpense).reduce(Decimal.zero) { $0 + $1.expenseAmount }
            let range = calendar.range(of: .day, in: .month, for: month)
            let lastDay = range?.count ?? 28
            let monthStart = calendar.startOfDay(for: month)
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
            let complete = calendar.startOfDay(for: firstDate) <= monthStart && calendar.startOfDay(for: referenceDate) >= monthEnd && lastDay > 0
            return MonthlyCashFlow(month: monthStart, income: income, expenses: expenses, isComplete: complete)
        }.sorted { $0.month < $1.month }
    }

    private static func categorySummaries(_ expenses: [Transaction], totalExpenses: Decimal) -> [SpendingCategorySummary] {
        Dictionary(grouping: expenses, by: \.category).map { category, values in
            let amount = values.reduce(Decimal.zero) { $0 + $1.expenseAmount }
            return SpendingCategorySummary(
                category: category,
                amount: amount,
                percentage: totalExpenses > 0 ? amount / totalExpenses * 100 : 0,
                transactionCount: values.count
            )
        }.sorted { $0.amount > $1.amount }
    }

    private static func weekdayAverages(_ expenses: [Transaction], firstDate: Date, referenceDate: Date) -> [WeekdaySpending] {
        let calendar = analysisCalendar
        let daily = Dictionary(grouping: expenses) { calendar.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(Decimal.zero) { $0 + $1.expenseAmount } }
        var totals: [Int: Decimal] = [:]
        var observed: [Int: Int] = [:]
        var cursor = calendar.startOfDay(for: firstDate)
        let end = calendar.startOfDay(for: referenceDate)
        while cursor <= end {
            let weekday = calendar.component(.weekday, from: cursor)
            totals[weekday, default: 0] += daily[cursor, default: 0]
            observed[weekday, default: 0] += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let symbols = calendar.shortWeekdaySymbols
        let displayOrder = [2, 3, 4, 5, 6, 7, 1]
        return displayOrder.map { weekday in
            WeekdaySpending(
                weekday: weekday,
                name: symbols[weekday - 1],
                average: totals[weekday, default: 0] / Decimal(max(observed[weekday, default: 0], 1))
            )
        }
    }
}
