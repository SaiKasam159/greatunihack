import Charts
import SwiftUI

struct CashFlowChartView: View {
    let cashFlow: [MonthlyCashFlow]
    @State private var selectedMonth: Date?

    private var selected: MonthlyCashFlow? {
        guard let selectedMonth else { return nil }
        return cashFlow.min { abs($0.month.timeIntervalSince(selectedMonth)) < abs($1.month.timeIntervalSince(selectedMonth)) }
    }

    var body: some View {
        SectionCard("Cash flow", subtitle: "Tap or drag to inspect a month") {
            if let selected {
                HStack {
                    Text(selected.month.formatted(.dateTime.month(.wide).year()))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Net \(AppFormatting.currency(selected.net))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected.net >= 0 ? Color.income : Color.expense)
                }
                HStack(spacing: 16) {
                    Label(AppFormatting.currency(selected.income), systemImage: "arrow.down.left")
                        .foregroundStyle(Color.income)
                    Label(AppFormatting.currency(selected.expenses), systemImage: "arrow.up.right")
                        .foregroundStyle(Color.expense)
                }
                .font(.caption)
            }

            Chart {
                ForEach(cashFlow) { item in
                    BarMark(
                        x: .value("Month", item.month, unit: .month),
                        y: .value("Amount", item.income)
                    )
                    .position(by: .value("Flow", "Income"))
                    .foregroundStyle(by: .value("Flow", "Income"))
                    BarMark(
                        x: .value("Month", item.month, unit: .month),
                        y: .value("Amount", item.expenses)
                    )
                    .position(by: .value("Flow", "Expenses"))
                    .foregroundStyle(by: .value("Flow", "Expenses"))
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.month, unit: .month))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .chartForegroundStyleScale(["Income": Color.income, "Expenses": Color.expense.opacity(0.72)])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(AppFormatting.compactCurrency(Decimal(amount))) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 14)
            .chartXSelection(value: $selectedMonth)
            .frame(height: 240)

            if cashFlow.contains(where: { !$0.isComplete }) {
                Text("First and last months are partial and excluded from monthly averages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
