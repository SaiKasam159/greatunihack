import Foundation
import FoundationModels

@available(iOS 26.0, *)
@MainActor
final class FoundationModelCoachService {
    private let model = SystemLanguageModel.default
    private var evaluationSession: LanguageModelSession?
    private var followUpSession: LanguageModelSession?
    private var latestEvaluationContext: String?

    var availability: AICoachAvailability {
        switch model.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unsupportedDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceDisabled
        case .unavailable(.modelNotReady):
            .modelNotReady
        @unknown default:
            .modelNotReady
        }
    }

    func evaluatePurchase(_ userMessage: String, financialContext: String) async throws -> PurchaseEvaluation {
        let activeSession = try structuredSession(financialContext: financialContext)
        let response = try await activeSession.respond(
            to: userMessage,
            generating: PurchaseEvaluation.self,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 1_200)
        )
        let evaluation = response.content
        latestEvaluationContext = Self.context(for: evaluation, purchasePrompt: userMessage)
        followUpSession = nil
        return evaluation
    }

    func respondToFollowUp(_ userMessage: String, financialContext: String) async throws -> String {
        let activeSession = try conversationalSession(financialContext: financialContext)
        let response = try await activeSession.respond(
            to: userMessage,
            generating: CoachFollowUpAnswer.self,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 800)
        )
        return response.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func structuredSession(financialContext: String) throws -> LanguageModelSession {
        guard availability == .available else { throw CoachServiceError.modelUnavailable }
        if let evaluationSession {
            return evaluationSession
        }
        let newSession = LanguageModelSession(
            model: model,
            instructions: Self.unifiedInstructions + "\n\n" + financialContext
        )
        evaluationSession = newSession
        return newSession
    }

    private func conversationalSession(financialContext: String) throws -> LanguageModelSession {
        guard availability == .available else { throw CoachServiceError.modelUnavailable }
        if let followUpSession { return followUpSession }
        let prior = latestEvaluationContext ?? "No previous evaluation details are available."
        let instructions = """
        You are FinancialFriday AI Coach. Answer follow-up questions conversationally using the supplied financial context and previous evaluation. Be concise, directly answer the question, and do not repeat all five perspectives unless explicitly requested. Never output JSON, schema keys, braces, or serialized structured data. Do not invent facts.

        FINANCIAL CONTEXT:
        \(financialContext)

        PREVIOUS EVALUATION:
        \(prior)
        """
        let newSession = LanguageModelSession(model: model, instructions: instructions)
        followUpSession = newSession
        return newSession
    }

    private static func context(for evaluation: PurchaseEvaluation, purchasePrompt: String) -> String {
        """
        Purchase request: \(purchasePrompt)
        Verdict: \(evaluation.verdict)
        Explanation: \(evaluation.verdictExplanation)
        Financial: \(evaluation.financial.shortVerdict) — \(evaluation.financial.reasoning)
        Research: \(evaluation.research.shortVerdict) — \(evaluation.research.reasoning)
        Devil's Advocate: \(evaluation.devilsAdvocate.shortVerdict) — \(evaluation.devilsAdvocate.reasoning)
        Lifestyle: \(evaluation.lifestyle.shortVerdict) — \(evaluation.lifestyle.reasoning)
        Future: \(evaluation.future.shortVerdict) — \(evaluation.future.reasoning)
        """
    }

    private static let unifiedInstructions = """
    You are FinancialFriday AI Coach, an on-device financial decision assistant. You use ONE model and evaluate purchase decisions through five perspectives in one cohesive response. Never claim to be five separate agents.

    Ground every financial statement in the supplied historical financial context. The calculated balance is historical and is not disposable income or a live bank balance. Never invent financial data, product specifications, market prices, reviews, competitors, lifestyle details, possessions, or future emotions. Clearly identify estimates and projections. If essential purchase information is missing, ask one concise follow-up question or give a clearly qualified assessment.

    PERSPECTIVE 1 — FINANCIAL: Can the user afford it? Analyse historical income, spending, calculated balance, recurring obligations, cash flow, and financial goals. Consider the impact on savings goals. Use actual supplied calculations whenever possible.

    PERSPECTIVE 2 — RESEARCH: Is it worth the price? Consider only product information supplied by the user: price, functionality, expected durability, usefulness, and stated alternatives. Acknowledge insufficient information; do not invent research.

    PERSPECTIVE 3 — DEVIL'S ADVOCATE: Why should the user not buy it? Identify hidden costs, risks, impulsive behaviour, unnecessary spending, and weaknesses in the case for buying. Present the strongest reasonable evidence-based argument against buying without automatically opposing every purchase.

    PERSPECTIVE 4 — LIFESTYLE: Does the user actually need it? Assess stated needs, intended usage, priorities, and everyday activities. Distinguish practical necessity from discretionary spending while recognising enjoyment as a legitimate reason. Do not infer missing lifestyle facts.

    PERSPECTIVE 5 — FUTURE: Might waiting be better? Evaluate effects over 3, 6, and 12 months. Compare buying now, delaying, and skipping. Consider opportunity cost, financial flexibility, and goal progress. Distinguish projections from guarantees and never claim to know future emotions.

    For a new purchase evaluation, fill the supplied structured schema. Set the final verdict to exactly BUY, WAIT, or SKIP. Give every perspective a compact short verdict plus meaningful reasoning. Include the optional current balance and balance-after-purchase figures only when they are relevant and can be derived reliably from the supplied context and purchase price. The final verdict must synthesize evidence across all perspectives, placing appropriate weight on financial risk. Do not use majority voting.

    For ordinary follow-up questions after an evaluation, answer conversationally and retain the prior purchase context instead of repeating all five perspectives unnecessarily.
    """
}

enum CoachServiceError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        "The on-device language model is not currently available."
    }
}
