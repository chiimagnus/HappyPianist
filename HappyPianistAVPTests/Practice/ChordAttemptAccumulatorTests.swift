import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func accumulatorMatchesChordWithinWindowAcrossMultiplePresses() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 0.6)
    var replay = PerformanceInputReplayCursor(events: [
        PerformanceReplayEvent(instant: .init(seconds: 1_000), source: "midi", payload: Set([60])),
        PerformanceReplayEvent(instant: .init(seconds: 1_000.2), source: "midi", payload: Set([64])),
        PerformanceReplayEvent(instant: .init(seconds: 1_000.45), source: "midi", payload: Set([67])),
    ])
    var outcomes: [StepAttemptMatchResult] = []

    replay.replay { event in
        outcomes.append(accumulator.register(
            pressedNotes: event.payload,
            expectedNotes: [60, 64, 67],
            tolerance: 0,
            at: event.instant.date
        ))
    }

    #expect(outcomes.map(\.isMatched) == [false, false, true])
}

@Test
func accumulatorResetsAfterWindowTimeout() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 0.6)
    let base = Date(timeIntervalSince1970: 2000)

    _ = accumulator.register(
        pressedNotes: [60],
        expectedNotes: [60, 64],
        tolerance: 0,
        at: base
    )

    let timedOut = accumulator.register(
        pressedNotes: [64],
        expectedNotes: [60, 64],
        tolerance: 0,
        at: base.addingTimeInterval(0.8)
    )
    #expect(timedOut.isMatched == false)
}
