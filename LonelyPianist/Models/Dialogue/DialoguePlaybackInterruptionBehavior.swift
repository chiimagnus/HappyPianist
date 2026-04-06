import Foundation

enum DialoguePlaybackInterruptionBehavior: String, CaseIterable, Identifiable, Sendable {
    case ignore
    case interrupt
    case queue

    static let userDefaultsKey = "dialoguePlaybackInterruptionBehavior"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ignore:
            return "A · Ignore"
        case .interrupt:
            return "B · Interrupt"
        case .queue:
            return "C · Queue"
        }
    }
}

