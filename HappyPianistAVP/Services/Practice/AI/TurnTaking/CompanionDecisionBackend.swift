import Foundation

enum CompanionParticipationMode: String, Equatable, Sendable {
    case support
    case sparse
    case yield
    case silent
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
}

struct CompanionDecision: Equatable, Sendable {
    let mode: CompanionParticipationMode
    let shouldRequestGeneration: Bool
    let shouldClearFutureWindows: Bool
    let requestWindowSeconds: TimeInterval
    let minRequestIntervalSeconds: TimeInterval
    let maxTokens: Int
}

protocol CompanionDecisionBackendProtocol: Sendable {
    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision
}
