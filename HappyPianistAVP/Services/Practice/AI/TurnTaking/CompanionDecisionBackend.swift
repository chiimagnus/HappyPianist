import Foundation

enum CompanionDecisionBackendKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case ruleBased = "rule_based"
    case networkBonjourQwen = "network_bonjour_qwen"

    var id: String { rawValue }
}

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
    let isAIPlaybackActive: Bool
    let userNoteOnSinceAIPlaybackStarted: Bool

    init(
        nowTimestampSeconds: TimeInterval,
        heldNotesCount: Int,
        sustainValue: Int,
        recentIOIMedianSeconds: TimeInterval?,
        recentVelocityTrend: Double,
        recentNoteDensityPerSecond: Double,
        lastUserEventTimestampSeconds: TimeInterval?,
        lastNoteOnTimestampSeconds: TimeInterval?,
        isAIPlaybackActive: Bool,
        userNoteOnSinceAIPlaybackStarted: Bool
    ) {
        self.nowTimestampSeconds = nowTimestampSeconds
        self.heldNotesCount = heldNotesCount
        self.sustainValue = sustainValue
        self.recentIOIMedianSeconds = recentIOIMedianSeconds
        self.recentVelocityTrend = recentVelocityTrend
        self.recentNoteDensityPerSecond = recentNoteDensityPerSecond
        self.lastUserEventTimestampSeconds = lastUserEventTimestampSeconds
        self.lastNoteOnTimestampSeconds = lastNoteOnTimestampSeconds
        self.isAIPlaybackActive = isAIPlaybackActive
        self.userNoteOnSinceAIPlaybackStarted = userNoteOnSinceAIPlaybackStarted
    }
}

enum CompanionDecisionValidationError: Error, Equatable {
    case invalidYieldPrerequisite
}

enum CompanionPlaybackPolicy: Equatable, Sendable {
    case preserve
    case clearUnstarted
    case yieldCurrent
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

    var playbackPolicy: CompanionPlaybackPolicy {
        switch action {
        case .listen:
            .clearUnstarted
        case .yield:
            .yieldCurrent
        case .support, .sparse, .respond:
            .preserve
        }
    }

    func validated(for input: CompanionDecisionInput) throws -> CompanionDecision {
        if action == .yield,
           (input.isAIPlaybackActive == false || input.userNoteOnSinceAIPlaybackStarted == false)
        {
            throw CompanionDecisionValidationError.invalidYieldPrerequisite
        }
        return self
    }
}

protocol CompanionDecisionBackendProtocol: Sendable {
    var kind: CompanionDecisionBackendKind { get }
    var displayName: String { get }

    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision
}
