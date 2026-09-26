import Foundation

enum CompanionDecisionBackendKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case ruleBased = "rule_based"
    case networkBonjourQwen = "network_bonjour_qwen"

    var id: String { rawValue }
}

enum CompanionAction: String, Codable, Equatable, Sendable {
    case listen
    case support
    case sparse
    case yield
    case respond
}

struct CompanionDecisionInput: Codable, Equatable, Sendable {
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

    init(
        nowTimestampSeconds: TimeInterval,
        heldNotesCount: Int,
        sustainValue: Int,
        recentIOIMedianSeconds: TimeInterval?,
        recentVelocityTrend: Double,
        recentNoteDensityPerSecond: Double,
        lastUserEventTimestampSeconds: TimeInterval?,
        lastNoteOnTimestampSeconds: TimeInterval?,
        activePitchCenter: Double?,
        isAIPlaybackActive: Bool
    ) {
        self.nowTimestampSeconds = nowTimestampSeconds
        self.heldNotesCount = heldNotesCount
        self.sustainValue = sustainValue
        self.recentIOIMedianSeconds = recentIOIMedianSeconds
        self.recentVelocityTrend = recentVelocityTrend
        self.recentNoteDensityPerSecond = recentNoteDensityPerSecond
        self.lastUserEventTimestampSeconds = lastUserEventTimestampSeconds
        self.lastNoteOnTimestampSeconds = lastNoteOnTimestampSeconds
        self.activePitchCenter = activePitchCenter
        self.isAIPlaybackActive = isAIPlaybackActive
    }
}

struct CompanionDecision: Equatable, Sendable {
    let action: CompanionAction
    let confidence: Double?

    init(action: CompanionAction, confidence: Double? = nil) {
        self.action = action
        self.confidence = confidence
    }

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
    var kind: CompanionDecisionBackendKind { get }
    var displayName: String { get }

    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision
}
