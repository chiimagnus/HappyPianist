import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func accumulatorMatchesChordWithinWindowAcrossMultiplePresses() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 0.6)
    let base = Date(timeIntervalSince1970: 1000)

    let first = accumulator.register(
        pressedNotes: [60],
        expectedNotes: [60, 64, 67],
        tolerance: 0,
        at: base
    )
    #expect(first == false)

    let second = accumulator.register(
        pressedNotes: [64],
        expectedNotes: [60, 64, 67],
        tolerance: 0,
        at: base.addingTimeInterval(0.2)
    )
    #expect(second == false)

    let third = accumulator.register(
        pressedNotes: [67],
        expectedNotes: [60, 64, 67],
        tolerance: 0,
        at: base.addingTimeInterval(0.45)
    )
    #expect(third == true)
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
    #expect(timedOut == false)
}
