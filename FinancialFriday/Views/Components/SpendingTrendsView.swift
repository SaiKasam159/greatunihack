import Charts
import SwiftUI

struct SpendingTrendsView: View {
    let values: [WeekdaySpending]

    var body: some View {
        SectionCard("Weekly rhythm", subtitle: "Average spend per calendar weekday, including no-spend days") {
            Chart(values) { item in
                BarMark(
                    x: .value("Day", item.name),
                    y: .value("Average", item.average)
                )
                .foregroundStyle(item.weekday == 6 ? Color.accent : Color.accent.opacity(0.45))
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text("£\(Int(amount))") }
                    }
                }
            }
            .frame(height: 210)
        }
    }
}
