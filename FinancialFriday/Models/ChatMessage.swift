import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

@available(iOS 26.0, *)
struct CoachChatMessage: Identifiable, Sendable {
    enum Content: Sendable {
        case text(String)
        case evaluation(PurchaseEvaluation)
    }

    let id: UUID
    let role: ChatMessage.Role
    let content: Content

    init(id: UUID = UUID(), role: ChatMessage.Role, content: Content) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum AICoachAvailability: Equatable, Sendable {
    case available
    case unsupportedOS
    case unsupportedDevice
    case appleIntelligenceDisabled
    case modelNotReady

    var title: String {
        switch self {
        case .available: "Apple Intelligence is ready"
        case .unsupportedOS: "Requires iOS 26 or later"
        case .unsupportedDevice: "Apple Intelligence unavailable"
        case .appleIntelligenceDisabled: "Apple Intelligence is off"
        case .modelNotReady: "On-device model not ready"
        }
    }

    var explanation: String {
        switch self {
        case .available:
            "Your purchase evaluation runs privately on this device."
        case .unsupportedOS:
            "Update to iOS 26 or later to use the on-device AI Coach. Overview and Goals remain available."
        case .unsupportedDevice:
            "This device does not support the on-device model required by AI Coach. Overview and Goals remain available."
        case .appleIntelligenceDisabled:
            "Enable Apple Intelligence in Settings to use AI Coach. No cloud AI fallback is used."
        case .modelNotReady:
            "Apple Intelligence is still preparing or downloading its on-device model. Try again when it is ready."
        }
    }
}
