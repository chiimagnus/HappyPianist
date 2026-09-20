import Foundation

enum CompanionAction: String, Equatable, Sendable {
    case listen
    case support
    case sparse
    case yield
    case respond
}

struct CompanionDecisionInput: Equatable, Sendable {
    let nowTimestampSeconds: TimeInterval
    let heldNotesCount: Int
    let sustainValue: Int
    let recentIOIMedianSeconds: TimeInterval?
    let recentVelocityTrend: Double
    let recentNoteDensityPerSecond: Double
    let lastUserEventTimestampSeconds: TimeInterval?
    let lastNoteOnTimestampSeconds: TimeInterval?
    let activePitchCenter: Double?
    let isAIPlaybackActive: Bool
}

struct CompanionDecision: Equatable, Sendable {
    let action: CompanionAction

    var shouldRequestGeneration: Bool {
        switch action {
        case .support, .sparse, .respond:
            true
        case .listen, .yield:
            false
        }
    }

    var shouldClearFutureWindows: Bool {
        switch action {
        case .listen, .yield:
            true
        case .support, .sparse, .respond:
            false
        }
    }
}

protocol CompanionDecisionBackendProtocol: Sendable {
    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision
}
