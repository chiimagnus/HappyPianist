import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func chordAccumulatorRequiresBothHandsWithinSameWindow() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 1.0)
    let t0 = PerformanceMonotonicInstant(seconds: 1)

    let first = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [60]),
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        expectedUnassignedNotes: [],
        at: t0
    )
    #expect(first.isMatched == false)

    let second = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(left: [48]),
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        expectedUnassignedNotes: [],
        at: t0.advanced(by: 0.1)
    )
    #expect(second.isMatched)
}

@Test
func chordAccumulatorRejectsCorrectPitchesPlayedByWrongHands() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 1)
    let outcome = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [48], left: [60]),
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        expectedUnassignedNotes: [],
        at: .init(seconds: 1)
    )

    #expect(outcome == .insufficientEvidence)
}

@Test
func chordAccumulatorMatchesUnknownScoreHandAgainstOverallPitch() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 1)
    let outcome = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(left: [60]),
        expectedRightNotes: [],
        expectedLeftNotes: [],
        expectedUnassignedNotes: [60],
        at: .init(seconds: 1)
    )

    #expect(outcome.isMatched)
}
