import SwiftUI

struct FinancialSummaryView: View {
    let summary: FinancialSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CALCULATED BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(AppFormatting.currency(summary.currentBalance))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75)
                Text("As of \(summary.referenceDate.formatted(date: .abbreviated, time: .omitted)) · £2,000 opening balance")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                metric("Income", value: summary.totalIncome, color: .income)
                metric("Expenses", value: summary.totalExpenses, color: .expense)
                metric("Net flow", value: summary.netCashFlow, color: summary.netCashFlow >= 0 ? .income : .expense)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.title2)
                .foregroundStyle(Color.accent.opacity(0.8))
                .padding(20)
        }
    }

    private func metric(_ title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(AppFormatting.compactCurrency(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
