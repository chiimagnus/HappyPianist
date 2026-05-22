import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func audioAccumulatorRequiresBothHandsWhenEnabled() {
    let accumulator = AudioStepAttemptAccumulator()
    let generation = 1
    let t0 = Date()

    accumulator.resetForNewStep(generation: generation)

    accumulator.register(event: DetectedNoteEvent(
        midiNote: 60,
        confidence: 1.0,
        onsetScore: 1.0,
        isOnset: true,
        timestamp: t0,
        generation: generation,
        source: .audio
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

    accumulator.register(event: DetectedNoteEvent(
        midiNote: 48,
        confidence: 1.0,
        onsetScore: 1.0,
        isOnset: true,
        timestamp: t0,
        generation: generation,
        source: .audio
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
    let t0 = Date()

    let first = accumulator.registerHandSeparated(
        pressedNotes: [60],
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        tolerance: 0,
        at: t0
    )
    #expect(first == false)

    let second = accumulator.registerHandSeparated(
        pressedNotes: [48],
        expectedRightNotes: [60],
        expectedLeftNotes: [48],
        tolerance: 0,
        at: t0.addingTimeInterval(0.1)
    )
    #expect(second == true)
}
