import Foundation

/// Deterministic baseline for companion decisions.
struct RuleBasedCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision {
        let timeSinceLastEvent = input.lastUserEventTimestampSeconds.map { max(0, input.nowTimestampSeconds - $0) }
        let timeSinceLastNoteOn = input.lastNoteOnTimestampSeconds.map { max(0, input.nowTimestampSeconds - $0) }
        let sustainIsDown = input.sustainValue >= 64
        let isFastFigure = (input.recentIOIMedianSeconds ?? 0.4) < 0.18
        let isDenseTexture = input.recentNoteDensityPerSecond >= 2.2
        let hasRecentActivity = (timeSinceLastEvent ?? 10) <= 1.2

        if hasRecentActivity == false {
            return CompanionDecision(action: .listen)
        }

        if isFastFigure || isDenseTexture {
            return CompanionDecision(action: .yield)
        }

        if input.heldNotesCount > 0 {
            if sustainIsDown || input.recentVelocityTrend > 4 {
                return CompanionDecision(action: .sparse)
            }
            return CompanionDecision(action: .support)
        }

        if (timeSinceLastNoteOn ?? 10) <= 0.35 {
            return CompanionDecision(action: .sparse)
        }

        if (timeSinceLastEvent ?? 10) <= 0.9 {
            return CompanionDecision(action: .support)
        }

        return CompanionDecision(action: .listen)
    }
}
