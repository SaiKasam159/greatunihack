import Foundation

struct RedZonePattern: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let severity: String
}

struct UpcomingSpendingWindow: Identifiable, Sendable {
    let date: Date
    let title: String
    let detail: String
    var id: Date { date }
}

struct FinancialExperienceAnalysis: Sendable {
    let inferredPayFrequency: String
    let inferredMonthFeeling: String
    let inferredSavingsLevel: String
    let inferredDebtLevel: String
    let heatLevels: [[Int]]
    let heatmapSummary: String
    let monthlyExpenses: [Decimal]
    let redZones: [RedZonePattern]
    let peakWeekday: WeekdaySpending
    let peakCategory: String
    let typicalEventSpend: Decimal
    let budgetOptions: [Decimal]
    let weeklyStreak: Int
    let latestWeekSpending: Decimal
    let weeklyOverrun: Decimal
    let repairTransfer: Decimal
    let repairTrim: Decimal
    let repairCategory: String
    let upcomingWindows: [UpcomingSpendingWindow]
    let fiveYearPlanBase: Decimal
    let fiveYearOverspending: Decimal
    let recoverableFiveYearSpend: Decimal

    static func make(summary: FinancialSummary) -> Self {
        let calendar = experienceCalendar
        let expenses = summary.transactions.filter(\.isExpense)
        let weekday = summary.weekdaySpending.max(by: { $0.average < $1.average })
            ?? WeekdaySpending(weekday: 6, name: "Fri", average: 0)

        let cells = heatmap(expenses: expenses, calendar: calendar)
        let peakCell = cells.averages.enumerated().flatMap { day, row in
            row.enumerated().map { (day, $0.offset, $0.element) }
        }.max { $0.2 < $1.2 }
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let periodNames = ["overnight", "morning", "late morning", "afternoon", "early evening", "evening"]
        let heatSummary = peakCell.map { "\(dayNames[$0.0]) \(periodNames[$0.1]) has your highest average spending." }
            ?? "No recurring spending window was found."

        let peakExpenses = expenses.filter { calendar.component(.weekday, from: $0.timestamp) == weekday.weekday }
        let categoryTotals = Dictionary(grouping: peakExpenses, by: \.category)
            .mapValues { $0.reduce(Decimal.zero) { $0 + $1.expenseAmount } }
        let peakCategory = categoryTotals.max(by: { $0.value < $1.value })?.key
            ?? summary.categories.first?.category ?? "Spending"

        let dailyPeakTotals = Dictionary(grouping: peakExpenses) { calendar.startOfDay(for: $0.timestamp) }
            .values.map { $0.reduce(Decimal.zero) { $0 + $1.expenseAmount } }.sorted()
        let typical = median(dailyPeakTotals)
        let budgetBase = max(typical, summary.averageDailySpending)
        let budgetOptions = [Decimal(string: "0.65")!, Decimal(string: "0.8")!, Decimal(1)]
            .map { roundedToFive(max(5, budgetBase * $0)) }

        let weeklyTotals = groupedWeeklyExpenses(expenses, calendar: calendar)
        let latestWeek = weeklyTotals.last?.amount ?? 0
        let overrun = max(0, latestWeek - summary.averageWeeklySpending)
        let repairTransfer = roundedToFive(max(0, overrun * Decimal(string: "0.4")!))
        let repairTrim = roundedToFive(max(0, overrun - repairTransfer))
        let repairCategory = summary.categories.first?.category ?? "discretionary spending"
        let streak = consecutiveWeeksWithinBaseline(weeklyTotals, baseline: summary.averageWeeklySpending)

        let redZones = makeRedZones(summary: summary, peak: weekday, peakCategory: peakCategory)
        let upcoming = makeUpcomingWindows(summary: summary, calendar: calendar)
        let recoverable = max(0, weekday.average - summary.averageDailySpending) * 52 * 5
        let base = max(0, summary.currentBalance + max(0, summary.averageMonthlyNetCashFlow) * 60)
        let incomeDates = summary.transactions.filter(\.isIncome).map(\.timestamp).sorted()
        let intervals = zip(incomeDates, incomeDates.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }.sorted()
        let typicalPayGap = intervals.isEmpty ? 0 : intervals[intervals.count / 2]
        let payFrequency = typicalPayGap == 0 ? "Irregular" : typicalPayGap <= 10 ? "Weekly" : typicalPayGap <= 40 ? "Monthly" : "Irregular"
        let monthFeeling = summary.averageMonthlyNetCashFlow > summary.averageMonthlyExpenses * Decimal(string: "0.2")! ? "Comfortable" : summary.averageMonthlyNetCashFlow >= 0 ? "Tight" : "Struggling"
        let savingsLevel = summary.currentBalance >= summary.averageMonthlyExpenses ? "One month+" : summary.currentBalance > 0 ? "Under one month" : "None"
        let debtKeywords = ["loan", "credit", "overdraft", "debt"]
        let hasDebt = summary.transactions.contains { transaction in debtKeywords.contains { transaction.merchant.localizedCaseInsensitiveContains($0) || transaction.category.localizedCaseInsensitiveContains($0) } }

        return Self(
            inferredPayFrequency: payFrequency,
            inferredMonthFeeling: monthFeeling,
            inferredSavingsLevel: savingsLevel,
            inferredDebtLevel: hasDebt ? "Card / overdraft" : "None",
            heatLevels: cells.levels,
            heatmapSummary: heatSummary,
            monthlyExpenses: summary.monthlyCashFlow.map(\.expenses),
            redZones: redZones,
            peakWeekday: weekday,
            peakCategory: peakCategory,
            typicalEventSpend: typical,
            budgetOptions: budgetOptions,
            weeklyStreak: streak,
            latestWeekSpending: latestWeek,
            weeklyOverrun: overrun,
            repairTransfer: repairTransfer,
            repairTrim: repairTrim,
            repairCategory: repairCategory,
            upcomingWindows: upcoming,
            fiveYearPlanBase: base,
            fiveYearOverspending: max(0, base - recoverable),
            recoverableFiveYearSpend: recoverable
        )
    }

    private static func heatmap(expenses: [Transaction], calendar: Calendar) -> (levels: [[Int]], averages: [[Decimal]]) {
        var totals = Array(repeating: Array(repeating: Decimal.zero, count: 6), count: 7)
        var dates = Set<Date>()
        for expense in expenses {
            let day = (calendar.component(.weekday, from: expense.timestamp) + 5) % 7
            let hour = calendar.component(.hour, from: expense.timestamp)
            let bin = hour < 6 ? 0 : hour < 9 ? 1 : hour < 12 ? 2 : hour < 15 ? 3 : hour < 18 ? 4 : 5
            totals[day][bin] += expense.expenseAmount
            dates.insert(calendar.startOfDay(for: expense.timestamp))
        }
        let observed = dates.reduce(into: Array(repeating: 0, count: 7)) { counts, date in
            counts[(calendar.component(.weekday, from: date) + 5) % 7] += 1
        }
        let averages = totals.enumerated().map { day, row in row.map { $0 / Decimal(max(observed[day], 1)) } }
        let maximum = averages.flatMap { $0 }.max() ?? 0
        let levels = averages.map { row in row.map { value in
            guard maximum > 0, value > 0 else { return 0 }
            return min(4, max(1, Int((value / maximum * 4).doubleValue.rounded(.up))))
        } }
        return (levels, averages)
    }

    private static func groupedWeeklyExpenses(_ expenses: [Transaction], calendar: Calendar) -> [(date: Date, amount: Decimal)] {
        Dictionary(grouping: expenses) { expense in
            calendar.dateInterval(of: .weekOfYear, for: expense.timestamp)?.start ?? calendar.startOfDay(for: expense.timestamp)
        }.map { ($0.key, $0.value.reduce(Decimal.zero) { $0 + $1.expenseAmount }) }.sorted { $0.date < $1.date }
    }

    private static func consecutiveWeeksWithinBaseline(_ weeks: [(date: Date, amount: Decimal)], baseline: Decimal) -> Int {
        guard baseline > 0 else { return 0 }
        var result = 0
        for week in weeks.reversed() {
            if week.amount <= baseline { result += 1 } else { break }
        }
        return result
    }

    private static func makeRedZones(summary: FinancialSummary, peak: WeekdaySpending, peakCategory: String) -> [RedZonePattern] {
        var values: [RedZonePattern] = [
            .init(id: "weekday", title: "\(peak.name) spending", detail: "Averages \(AppFormatting.currency(peak.average)) per observed day", severity: "High"),
            .init(id: "category", title: peakCategory, detail: "Largest category in your peak window", severity: "High")
        ]
        if let category = summary.categories.first {
            values.append(.init(id: "top-category", title: category.category, detail: "\(category.percentage.doubleValue.formatted(.number.precision(.fractionLength(1))))% of all expenses", severity: "Medium"))
        }
        if let merchant = summary.highestSpendingMerchant {
            values.append(.init(id: "merchant", title: merchant, detail: "Highest total merchant spend", severity: "Low"))
        }
        return Array(values.prefix(4))
    }

    private static func makeUpcomingWindows(summary: FinancialSummary, calendar: Calendar) -> [UpcomingSpendingWindow] {
        let topDays = summary.weekdaySpending.sorted { $0.average > $1.average }.prefix(3)
        return topDays.enumerated().compactMap { offset, day in
            guard let date = nextDate(forWeekday: day.weekday, after: calendar.date(byAdding: .day, value: offset, to: .now) ?? .now, calendar: calendar) else { return nil }
            let category = topCategory(on: day.weekday, transactions: summary.transactions, calendar: calendar)
            return UpcomingSpendingWindow(date: date, title: category, detail: "Typical \(day.name) spend \(AppFormatting.currency(day.average))")
        }.sorted { $0.date < $1.date }
    }

    private static func topCategory(on weekday: Int, transactions: [Transaction], calendar: Calendar) -> String {
        let matching = transactions.filter { $0.isExpense && calendar.component(.weekday, from: $0.timestamp) == weekday }
        let totals = Dictionary(grouping: matching, by: \.category).mapValues { $0.reduce(Decimal.zero) { $0 + $1.expenseAmount } }
        return totals.max(by: { $0.value < $1.value })?.key ?? "Spending window"
    }

    private static func nextDate(forWeekday weekday: Int, after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
    }

    private static func median(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    private static func roundedToFive(_ value: Decimal) -> Decimal {
        Decimal((value.doubleValue / 5).rounded() * 5)
    }

    private static var experienceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return calendar
    }
}
