import SwiftData
import SwiftUI

struct GoalDetailView: View {
    let goal: FinancialGoal
    let summary: FinancialSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editing = false
    @State private var confirmingDelete = false

    private var plan: GoalPlan? {
        GoalCalculationService.plan(target: goal.targetAmount, deadline: goal.deadline, historicalMonthlyNet: summary.averageMonthlyNetCashFlow)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                targetCard
                if let plan { contributionCard(plan) }
                feasibilityCard
                Text("This estimate uses historical complete-month net cash flow. It is planning guidance, not a guarantee, and no savings contributions are inferred from transactions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { GoalEditorView(goal: goal) }
        .alert("Delete this goal?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                modelContext.delete(goal)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    private var targetCard: some View {
        SectionCard("Target") {
            Text(AppFormatting.currency(goal.targetAmount))
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Label(goal.deadline.formatted(date: .long, time: .omitted), systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func contributionCard(_ plan: GoalPlan) -> some View {
        SectionCard("Required savings rate", subtitle: "Calculated from today to the deadline") {
            HStack(spacing: 12) {
                contributionMetric("Monthly", plan.monthlyContribution)
                contributionMetric("Weekly", plan.weeklyContribution)
            }
            Label("\(plan.daysRemaining) days remaining", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func contributionMetric(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(AppFormatting.currency(amount)).font(.title3.weight(.bold)).minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var feasibilityCard: some View {
        SectionCard("Estimated feasibility") {
            if let plan {
                Label(plan.feasibility.rawValue, systemImage: feasibilityIcon(plan.feasibility))
                    .font(.headline)
                    .foregroundStyle(feasibilityColor(plan.feasibility))
                Text("Historical average monthly net flow: \(AppFormatting.currency(summary.averageMonthlyNetCashFlow))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Deadline has passed", systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(Color.expense)
            }
        }
    }

    private func feasibilityIcon(_ value: GoalPlan.Feasibility) -> String {
        switch value {
        case .comfortable: "checkmark.circle.fill"
        case .tight: "exclamationmark.circle.fill"
        case .unavailable: "minus.circle.fill"
        }
    }

    private func feasibilityColor(_ value: GoalPlan.Feasibility) -> Color {
        switch value {
        case .comfortable: .income
        case .tight: .orange
        case .unavailable: .expense
        }
    }
}
