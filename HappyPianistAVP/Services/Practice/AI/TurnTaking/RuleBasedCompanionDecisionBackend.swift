import Foundation

/// Deterministic baseline for companion participation decisions.
struct RuleBasedCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision {
        let timeSinceLastEvent = input.lastUserEventTimestampSeconds.map { max(0, input.nowTimestampSeconds - $0) }
        let timeSinceLastNoteOn = input.lastNoteOnTimestampSeconds.map { max(0, input.nowTimestampSeconds - $0) }
        let sustainIsDown = input.sustainValue >= 64
        let isFastFigure = (input.recentIOIMedianSeconds ?? 0.4) < 0.18
        let isDenseTexture = input.recentNoteDensityPerSecond >= 2.2
        let hasRecentActivity = (timeSinceLastEvent ?? 10) <= 1.2

        if hasRecentActivity == false {
            return CompanionDecision(
                mode: .silent,
                shouldRequestGeneration: false,
                shouldClearFutureWindows: true,
                requestWindowSeconds: 0,
                minRequestIntervalSeconds: 0.30,
                maxTokens: 0
            )
        }

        if isFastFigure || isDenseTexture {
            return CompanionDecision(
                mode: .yield,
                shouldRequestGeneration: false,
                shouldClearFutureWindows: true,
                requestWindowSeconds: 0,
                minRequestIntervalSeconds: 0.22,
                maxTokens: 0
            )
        }

        if input.heldNotesCount > 0 {
            if sustainIsDown || input.recentVelocityTrend > 4 {
                return CompanionDecision(
                    mode: .sparse,
                    shouldRequestGeneration: true,
                    shouldClearFutureWindows: false,
                    requestWindowSeconds: 0.45,
                    minRequestIntervalSeconds: 0.18,
                    maxTokens: 28
                )
            }

            return CompanionDecision(
                mode: .support,
                shouldRequestGeneration: true,
                shouldClearFutureWindows: false,
                requestWindowSeconds: 0.70,
                minRequestIntervalSeconds: 0.24,
                maxTokens: 40
            )
        }

        if (timeSinceLastNoteOn ?? 10) <= 0.35 {
            return CompanionDecision(
                mode: .sparse,
                shouldRequestGeneration: true,
                shouldClearFutureWindows: false,
                requestWindowSeconds: 0.45,
                minRequestIntervalSeconds: 0.18,
                maxTokens: 24
            )
        }

        if (timeSinceLastEvent ?? 10) <= 0.9 {
            return CompanionDecision(
                mode: .support,
                shouldRequestGeneration: true,
                shouldClearFutureWindows: false,
                requestWindowSeconds: 0.60,
                minRequestIntervalSeconds: 0.22,
                maxTokens: 36
            )
        }

        return CompanionDecision(
            mode: .silent,
            shouldRequestGeneration: false,
            shouldClearFutureWindows: true,
            requestWindowSeconds: 0,
            minRequestIntervalSeconds: 0.30,
            maxTokens: 0
        )
    }
}
