import Foundation

/// Pure overlap-control estimator for the continuous duet engine.
struct DuetTurnTakingCore: Sendable {
    enum Mode: String, Equatable, Sendable {
        case support
        case sparse
        case yield
        case silent
    }

    struct ControlSnapshot: Equatable, Sendable {
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

    struct Decision: Equatable, Sendable {
        let mode: Mode
        let shouldRequestGeneration: Bool
        let shouldClearFutureWindows: Bool
        let requestWindowSeconds: TimeInterval
        let minRequestIntervalSeconds: TimeInterval
        let maxTokens: Int
    }

    init() {}

    mutating func evaluate(_ snapshot: ControlSnapshot) -> Decision {
        let timeSinceLastEvent = snapshot.lastUserEventTimestampSeconds.map { max(0, snapshot.nowTimestampSeconds - $0) }
        let timeSinceLastNoteOn = snapshot.lastNoteOnTimestampSeconds.map { max(0, snapshot.nowTimestampSeconds - $0) }
        let sustainIsDown = snapshot.sustainValue >= 64
        let isFastFigure = (snapshot.recentIOIMedianSeconds ?? 0.4) < 0.18
        let isDenseTexture = snapshot.recentNoteDensityPerSecond >= 2.2
        let hasRecentActivity = (timeSinceLastEvent ?? 10) <= 1.2

        if hasRecentActivity == false {
            return Decision(
                mode: .silent,
                shouldRequestGeneration: false,
                shouldClearFutureWindows: true,
                requestWindowSeconds: 0,
                minRequestIntervalSeconds: 0.30,
                maxTokens: 0
            )
        }

        if isFastFigure || isDenseTexture {
            return Decision(
                mode: .yield,
                shouldRequestGeneration: false,
                shouldClearFutureWindows: true,
                requestWindowSeconds: 0,
                minRequestIntervalSeconds: 0.22,
                maxTokens: 0
            )
        }

        if snapshot.heldNotesCount > 0 {

            if sustainIsDown || snapshot.recentVelocityTrend > 4 {
                return Decision(
                    mode: .sparse,
                    shouldRequestGeneration: true,
                    shouldClearFutureWindows: false,
                    requestWindowSeconds: 0.45,
                    minRequestIntervalSeconds: 0.18,
                    maxTokens: 28
                )
            }

            return Decision(
                mode: .support,
                shouldRequestGeneration: true,
                shouldClearFutureWindows: false,
                requestWindowSeconds: 0.70,
                minRequestIntervalSeconds: 0.24,
                maxTokens: 40
            )
        }

        if (timeSinceLastNoteOn ?? 10) <= 0.35 {
            return Decision(
                mode: .sparse,
                shouldRequestGeneration: true,
                shouldClearFutureWindows: false,
                requestWindowSeconds: 0.45,
                minRequestIntervalSeconds: 0.18,
                maxTokens: 24
            )
        }

        if (timeSinceLastEvent ?? 10) <= 0.9 {
            return Decision(
                mode: .support,
                shouldRequestGeneration: true,
                shouldClearFutureWindows: false,
                requestWindowSeconds: 0.60,
                minRequestIntervalSeconds: 0.22,
                maxTokens: 36
            )
        }

        return Decision(
            mode: .silent,
            shouldRequestGeneration: false,
            shouldClearFutureWindows: true,
            requestWindowSeconds: 0,
            minRequestIntervalSeconds: 0.30,
            maxTokens: 0
        )
    }

    mutating func reset() {}
}
