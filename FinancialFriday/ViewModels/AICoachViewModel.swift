import Foundation
import Observation

@available(iOS 26.0, *)
@MainActor
@Observable
final class AICoachViewModel {
    private let coachService = FoundationModelCoachService()

    private(set) var messages: [CoachChatMessage] = []
    private(set) var isGenerating = false
    private(set) var availability: AICoachAvailability = .modelNotReady
    var errorMessage: String?

    init() {
        availability = coachService.availability
    }

    func refreshAvailability() {
        availability = coachService.availability
    }

    func send(_ text: String, financialContext: String) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !isGenerating, availability == .available else { return }

        errorMessage = nil
        messages.append(CoachChatMessage(role: .user, content: .text(cleanText)))
        isGenerating = true
        defer { isGenerating = false }

        do {
            if hasEvaluation && !isNewPurchaseRequest(cleanText) {
                let response = try await coachService.respondToFollowUp(cleanText, financialContext: financialContext)
                guard !response.isEmpty else {
                    errorMessage = "The on-device model returned an empty response. Please try again."
                    return
                }
                messages.append(CoachChatMessage(role: .assistant, content: .text(response)))
            } else {
                let evaluation = try await coachService.evaluatePurchase(cleanText, financialContext: financialContext)
                messages.append(CoachChatMessage(role: .assistant, content: .evaluation(evaluation)))
            }
        } catch {
            refreshAvailability()
            if availability == .available {
                errorMessage = "The on-device model could not complete that response. \(error.localizedDescription)"
            }
        }
    }

    private var hasEvaluation: Bool {
        messages.contains { message in
            if case .evaluation = message.content { return true }
            return false
        }
    }

    private func isNewPurchaseRequest(_ text: String) -> Bool {
        let value = text.lowercased()
        let purchasePhrases = [
            "should i buy", "can i buy", "can i afford", "thinking of buying",
            "want to buy", "want to get", "purchase", "costs ", "cost ",
            "price ", "spend ", "order "
        ]
        let includesPurchasePhrase = purchasePhrases.contains { value.contains($0) }
        let includesCurrencyAmount = value.contains("£") || value.contains("$") || value.contains("€")
        return includesPurchasePhrase || includesCurrencyAmount
    }
}
