import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func duetTurnTakingCoreReturnsYieldForDenseHeldTexture() {
    var core = DuetTurnTakingCore()
    let decision = core.evaluate(
        .init(
            nowTimestampSeconds: 10.0,
            heldNotesCount: 2,
            sustainValue: 0,
            recentIOIMedianSeconds: 0.12,
            recentVelocityTrend: 2,
            recentNoteDensityPerSecond: 3.0,
            lastUserEventTimestampSeconds: 9.8,
            lastNoteOnTimestampSeconds: 9.9,
            activePitchCenter: 64
        )
    )

    #expect(decision.mode == .yield)
    #expect(decision.shouldRequestGeneration == false)
    #expect(decision.shouldClearFutureWindows)
}

@Test
func duetTurnTakingCoreReturnsSparseForSustainLedHeldTexture() {
    var core = DuetTurnTakingCore()
    let decision = core.evaluate(
        .init(
            nowTimestampSeconds: 5.0,
            heldNotesCount: 1,
            sustainValue: 127,
            recentIOIMedianSeconds: 0.32,
            recentVelocityTrend: 8,
            recentNoteDensityPerSecond: 1.0,
            lastUserEventTimestampSeconds: 4.9,
            lastNoteOnTimestampSeconds: 4.85,
            activePitchCenter: 60
        )
    )

    #expect(decision.mode == .sparse)
    #expect(decision.shouldRequestGeneration)
    #expect(abs(decision.requestWindowSeconds - 0.45) < 1e-9)
    #expect(decision.maxTokens == 28)
}

@Test
func duetTurnTakingCoreReturnsSupportForRecentHeldLine() {
    var core = DuetTurnTakingCore()
    let decision = core.evaluate(
        .init(
            nowTimestampSeconds: 20.0,
            heldNotesCount: 1,
            sustainValue: 0,
            recentIOIMedianSeconds: 0.28,
            recentVelocityTrend: 0,
            recentNoteDensityPerSecond: 1.4,
            lastUserEventTimestampSeconds: 19.7,
            lastNoteOnTimestampSeconds: 19.8,
            activePitchCenter: 67
        )
    )

    #expect(decision.mode == .support)
    #expect(decision.shouldRequestGeneration)
    #expect(decision.shouldClearFutureWindows == false)
    #expect(abs(decision.requestWindowSeconds - 0.70) < 1e-9)
}

@Test
func duetTurnTakingCoreReturnsSilentForStaleInput() {
    var core = DuetTurnTakingCore()
    let decision = core.evaluate(
        .init(
            nowTimestampSeconds: 100.0,
            heldNotesCount: 0,
            sustainValue: 0,
            recentIOIMedianSeconds: nil,
            recentVelocityTrend: 0,
            recentNoteDensityPerSecond: 0,
            lastUserEventTimestampSeconds: 98.0,
            lastNoteOnTimestampSeconds: 98.0,
            activePitchCenter: nil
        )
    )

    #expect(decision.mode == .silent)
    #expect(decision.shouldRequestGeneration == false)
    #expect(decision.shouldClearFutureWindows)
}
