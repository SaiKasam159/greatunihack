import SwiftData
import SwiftUI

@available(iOS 26.0, *)
struct AICoachView: View {
    let summary: FinancialSummary
    @Query(sort: \FinancialGoal.deadline) private var goals: [FinancialGoal]
    @State private var viewModel = AICoachViewModel()
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        welcome
                        if viewModel.availability != .available {
                            availabilityCard
                        }
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isGenerating {
                            thinkingIndicator.id("thinking")
                        }
                        if let errorMessage = viewModel.errorMessage {
                            errorCard(errorMessage).id("error")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded { isComposerFocused = false }
                )
                .background(Color(.systemGroupedBackground))
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let latest = viewModel.messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(latest.id, anchor: .bottom) }
                }
                .onChange(of: viewModel.isGenerating) { _, generating in
                    if generating {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
            .task { viewModel.refreshAvailability() }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "apple.intelligence")
                .font(.title2)
                .foregroundStyle(Color.accent)
                .frame(width: 42, height: 42)
                .background(Color.accent.opacity(0.1), in: Circle())
            Text("Thinking about buying something?")
                .font(.title3.weight(.bold))
            Text("Tell me what it is and how much it costs. I'll evaluate it from five different perspectives.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                draft = "Should I buy an iPhone for £1,000?"
                isComposerFocused = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                    Text("Should I buy an iPhone for £1,000?")
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.availability != .available)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var availabilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "apple.intelligence")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.availability.title).font(.subheadline.weight(.semibold))
                Text(viewModel.availability.explanation).font(.caption).foregroundStyle(.secondary)
                if viewModel.availability == .modelNotReady {
                    Button("Check again") { viewModel.refreshAvailability() }
                        .font(.caption.weight(.semibold))
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Considering all five perspectives…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.trailing, 52)
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Color.expense)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.expense.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about a purchase", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { submit() }

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Color.accent : Color.secondary.opacity(0.35), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isGenerating &&
        viewModel.availability == .available
    }

    private func submit() {
        guard canSend else { return }
        let message = draft
        draft = ""
        let context = FinancialContextBuilder.make(summary: summary, goals: goals)
        Task { await viewModel.send(message, financialContext: context) }
    }
}

@available(iOS 26.0, *)
private struct ChatBubble: View {
    let message: CoachChatMessage

    var body: some View {
        switch message.content {
        case .text(let text):
            textBubble(text)
        case .evaluation(let evaluation):
            PurchaseEvaluationView(evaluation: evaluation)
        }
    }

    private func textBubble(_ text: String) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(
                    message.role == .user ? Color.accent : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            if message.role == .assistant { Spacer(minLength: 32) }
        }
        .frame(maxWidth: .infinity)
    }
}

struct AIUnsupportedView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(AICoachAvailability.unsupportedOS.title, systemImage: "apple.intelligence")
            } description: {
                Text(AICoachAvailability.unsupportedOS.explanation)
            }
            .navigationTitle("AI Coach")
        }
    }
}
