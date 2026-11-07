import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable(description: "A concise purchase recommendation grounded in the supplied financial and product context.")
struct PurchaseEvaluation: Sendable {
    @Guide(description: "The overall recommendation.", .anyOf(["BUY", "WAIT", "SKIP"]))
    var verdict: String

    @Guide(description: "A short, direct explanation of the final verdict in one or two sentences.")
    var verdictExplanation: String

    @Guide(description: "The historical calculated balance in GBP, only when it is relevant and available.")
    var currentBalance: Decimal?

    @Guide(description: "The estimated balance in GBP immediately after the proposed purchase, only when a reliable purchase price and balance are available.")
    var balanceAfterPurchase: Decimal?

    var financial: PerspectiveEvaluation
    var research: PerspectiveEvaluation
    var devilsAdvocate: PerspectiveEvaluation
    var lifestyle: PerspectiveEvaluation
    var future: PerspectiveEvaluation
}

@available(iOS 26.0, *)
@Generable(description: "One compact perspective within a purchase evaluation.")
struct PerspectiveEvaluation: Sendable {
    @Guide(description: "A very short verdict or takeaway, ideally under eight words.")
    var shortVerdict: String

    @Guide(description: "Concise evidence-based reasoning for this perspective. Do not invent missing facts.")
    var reasoning: String
}

@available(iOS 26.0, *)
@Generable(description: "A concise conversational answer to a follow-up about the previous purchase evaluation.")
struct CoachFollowUpAnswer: Sendable {
    @Guide(description: "Plain conversational text only. Never include JSON, keys, braces, or a repeated five-perspective schema.")
    var answer: String
}
