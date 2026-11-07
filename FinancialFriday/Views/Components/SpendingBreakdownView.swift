import Charts
import SwiftUI

struct SpendingBreakdownView: View {
    let categories: [SpendingCategorySummary]
    @State private var showAll = false

    private var visibleCategories: [SpendingCategorySummary] {
        Array(categories.prefix(showAll ? categories.count : 6))
    }

    var body: some View {
        SectionCard("Spending breakdown", subtitle: "Across the full dataset") {
            Chart(visibleCategories) { item in
                BarMark(
                    x: .value("Spend", item.amount),
                    y: .value("Category", item.category)
                )
                .foregroundStyle(Color.accent.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(AppFormatting.compactCurrency(item.amount))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption) }
            }
            .frame(height: CGFloat(visibleCategories.count * 42))

            VStack(spacing: 10) {
                ForEach(visibleCategories.prefix(4)) { item in
                    HStack {
                        Text(item.category).font(.subheadline)
                        Spacer()
                        Text("\(item.percentage.doubleValue.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("· \(item.transactionCount) txns")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if categories.count > 6 {
                Button(showAll ? "Show less" : "Show all categories") {
                    withAnimation(.snappy) { showAll.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }
}
