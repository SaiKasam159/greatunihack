import Foundation

enum GoalCalculationService {
    static func plan(target: Decimal, deadline: Date, historicalMonthlyNet: Decimal, from startDate: Date = .now) -> GoalPlan? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: deadline)
        guard target > 0, end > start else { return nil }
        let days = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 1)
        let weeks = Decimal(days) / 7
        let averageDaysPerMonth = Decimal(string: "30.4375") ?? 30
        let months = Decimal(days) / averageDaysPerMonth
        let monthly = target / months
        let weekly = target / weeks
        let feasibility: GoalPlan.Feasibility
        if historicalMonthlyNet <= 0 { feasibility = .unavailable }
        else if monthly <= historicalMonthlyNet { feasibility = .comfortable }
        else { feasibility = .tight }
        return GoalPlan(daysRemaining: days, monthlyContribution: monthly, weeklyContribution: weekly, feasibility: feasibility)
    }
}
