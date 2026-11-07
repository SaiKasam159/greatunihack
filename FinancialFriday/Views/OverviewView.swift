import SwiftUI

struct OverviewView: View {
    let summary: FinancialSummary

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    FinancialSummaryView(summary: summary)
                    CashFlowChartView(cashFlow: summary.monthlyCashFlow)
                    SpendingBreakdownView(categories: summary.categories)
                    SpendingInsightsView(insights: summary.insights)
                    SpendingTrendsView(values: summary.weekdaySpending)
                    methodologyNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FinancialFriday")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var methodologyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
            Text("Calculated from bundled transaction history as of \(summary.referenceDate.formatted(date: .long, time: .omitted)). This is a historical estimate, not a live bank balance.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
