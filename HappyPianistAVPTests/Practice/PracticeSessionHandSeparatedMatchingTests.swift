import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func audioAccumulatorRequiresBothHandsWhenEnabled() {
    let accumulator = AudioStepAttemptAccumulator()
    let generation = 1
    let t0 = PerformanceMonotonicInstant(seconds: 1)

    accumulator.resetForNewStep(generation: generation)

    accumulator.register(evidence: TargetAudioEvidence(
        targetMIDINotes: [60],
        targetConfidenceByMIDINote: [60: 1],
        wrongConfidenceByMIDINote: [:],
        onsetScore: 1.0,
        isOnset: true,
        timestamp: t0,
        generation: generation
    ))

    let rightOnly = accumulator.evaluateHandSeparated(
        expectedRightMIDINotes: [60],
        expectedLeftMIDINotes: [48],
        wrongCandidateMIDINotes: [],
        generation: generation,
        at: t0
    )
    let rightOnlyMatched: Bool = {
        if case .matched = rightOnly { return true }
        return false
    }()
    #expect(rightOnlyMatched == false)

    accumulator.register(evidence: TargetAudioEvidence(
        targetMIDINotes: [48],
        targetConfidenceByMIDINote: [48: 1],
        wrongConfidenceByMIDINote: [:],
        onsetScore: 1.0,
        isOnset: true,
        timestamp: t0,
        generation: generation
    ))

    let both = accumulator.evaluateHandSeparated(
        expectedRightMIDINotes: [60],
        expectedLeftMIDINotes: [48],
        wrongCandidateMIDINotes: [],
        generation: generation,
        at: t0
    )
    let bothMatched: Bool = {
        if case .matched = both { return true }
        return false
    }()
    #expect(bothMatched == true)
}

@Test
func chordAccumulatorRequiresBothHandsWithinSameWindow() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 1.0)
    let t0 = PerformanceMonotonicInstant(seconds: 1)

    let first = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [60]),
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        expectedUnassignedNotes: [],
        tolerance: 0,
        at: t0
    )
    #expect(first.isMatched == false)

    let second = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(left: [48]),
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        expectedUnassignedNotes: [],
        tolerance: 0,
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
        tolerance: 0,
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
        tolerance: 0,
        at: .init(seconds: 1)
    )

    #expect(outcome.isMatched)
}
