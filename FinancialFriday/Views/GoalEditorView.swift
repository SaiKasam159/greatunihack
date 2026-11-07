import SwiftData
import SwiftUI

struct GoalEditorView: View {
    let goal: FinancialGoal?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var amountText: String
    @State private var deadline: Date
    @State private var showValidation = false

    init(goal: FinancialGoal?) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _amountText = State(initialValue: goal.map { NSDecimalNumber(decimal: $0.targetAmount).stringValue } ?? "")
        _deadline = State(initialValue: goal?.deadline ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
    }

    private var parsedAmount: Decimal? { AppFormatting.decimal(from: amountText) }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (parsedAmount ?? 0) > 0 &&
        Calendar.current.startOfDay(for: deadline) > Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Goal name", text: $name)
                        .textInputAutocapitalization(.words)
                    HStack {
                        Text("£").foregroundStyle(.secondary)
                        TextField("Target amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Deadline", selection: $deadline, in: tomorrow..., displayedComponents: .date)
                }

                Section {
                    Text("FinancialFriday calculates the contribution needed from today. It does not assume your balance or past surplus has already been saved toward this goal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if showValidation && !isValid {
                    Section {
                        Label("Enter a name, a target above £0, and a future deadline.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.expense)
                    }
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
        }
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private func save() {
        guard isValid, let amount = parsedAmount else {
            showValidation = true
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let goal {
            goal.name = cleanName
            goal.targetAmount = amount
            goal.deadline = deadline
        } else {
            modelContext.insert(FinancialGoal(name: cleanName, targetAmount: amount, deadline: deadline))
        }
        dismiss()
    }
}
