import SwiftData
import SwiftUI

struct GoalsView: View {
    let summary: FinancialSummary
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinancialGoal.deadline) private var goals: [FinancialGoal]
    @State private var showingNewGoal = false

    var body: some View {
        NavigationStack {
            Group {
                if goals.isEmpty { emptyState }
                else { goalsList }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewGoal = true } label: {
                        Label("New goal", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewGoal) {
                GoalEditorView(goal: nil)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Plan your first goal", systemImage: "target")
        } description: {
            Text("Set a target and deadline to see the savings rate your plan requires.")
        } actions: {
            Button("Create a goal") { showingNewGoal = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
        }
    }

    private var goalsList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                planningContext
                ForEach(goals) { goal in
                    NavigationLink {
                        GoalDetailView(goal: goal, summary: summary)
                    } label: {
                        GoalRow(goal: goal, summary: summary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { modelContext.delete(goal) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var planningContext: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Historical planning baseline").font(.subheadline.weight(.semibold))
                Text("Average complete-month net flow: \(AppFormatting.currency(summary.averageMonthlyNetCashFlow)). This is context, not money assigned to a goal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GoalRow: View {
    let goal: FinancialGoal
    let summary: FinancialSummary

    var plan: GoalPlan? {
        GoalCalculationService.plan(target: goal.targetAmount, deadline: goal.deadline, historicalMonthlyNet: summary.averageMonthlyNetCashFlow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name).font(.headline)
                    Text("Target \(AppFormatting.currency(goal.targetAmount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            Divider()
            HStack {
                Label(goal.deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                Spacer()
                if let plan {
                    Text("\(AppFormatting.currency(plan.monthlyContribution))/mo")
                        .fontWeight(.semibold)
                } else {
                    Text("Deadline passed").foregroundStyle(Color.expense)
                }
            }
            .font(.caption)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
