import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func simultaneousChordUsesActualOnsetSpread() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 0.6, simultaneousSpreadSeconds: 0.08)

    let first = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [60]),
        expectedRightNotes: [60, 64],
        expectedLeftNotes: [],
        expectedUnassignedNotes: [],
        tolerance: 0,
        onsetExpectation: .simultaneous,
        at: .init(seconds: 1)
    )
    let tooWide = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [64]),
        expectedRightNotes: [60, 64],
        expectedLeftNotes: [],
        expectedUnassignedNotes: [],
        tolerance: 0,
        onsetExpectation: .simultaneous,
        at: .init(seconds: 1.2)
    )

    #expect(first == .insufficientEvidence)
    #expect(tooWide == .insufficientEvidence)
}

@Test
func rolledChordAcceptsOnsetsAcrossConfiguredSpan() {
    let accumulator = ChordAttemptAccumulator(windowSeconds: 0.6, simultaneousSpreadSeconds: 0.08)

    _ = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [60]),
        expectedRightNotes: [60, 64, 67],
        expectedLeftNotes: [],
        expectedUnassignedNotes: [],
        tolerance: 0,
        onsetExpectation: .rolled,
        at: .init(seconds: 1)
    )
    _ = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [64]),
        expectedRightNotes: [60, 64, 67],
        expectedLeftNotes: [],
        expectedUnassignedNotes: [],
        tolerance: 0,
        onsetExpectation: .rolled,
        at: .init(seconds: 1.2)
    )
    let result = accumulator.registerHandSeparated(
        evidence: HandSeparatedNoteEvidence(right: [67]),
        expectedRightNotes: [60, 64, 67],
        expectedLeftNotes: [],
        expectedUnassignedNotes: [],
        tolerance: 0,
        onsetExpectation: .rolled,
        at: .init(seconds: 1.45)
    )

    #expect(result == .matched)
}

@Test
@MainActor
func midiMatcherInfersRolledTargetFromScoreOffsets() {
    let matcher = MIDIPracticeStepMatcher()
    matcher.reset(stepIndex: 0, expectedNotes: [
        PracticeStepNote(midiNote: 60, staff: 1, onTickOffset: 0, handAssignment: rightHand),
        PracticeStepNote(midiNote: 64, staff: 1, onTickOffset: 120, handAssignment: rightHand),
    ])

    #expect(matcher.register(midiObservation(note: 60, seconds: 1)) == .insufficientEvidence)
    #expect(matcher.register(midiObservation(note: 64, seconds: 1.4)) == .matched)
}

@Test
@MainActor
func midiMatcherRequiresObservedReleaseOnlyForRepeatedTarget() {
    let matcher = MIDIPracticeStepMatcher()
    let note = PracticeStepNote(midiNote: 60, staff: 1, handAssignment: rightHand)
    matcher.reset(stepIndex: 0, expectedNotes: [note])
    #expect(matcher.register(midiObservation(note: 60, seconds: 1)) == .matched)

    matcher.reset(stepIndex: 1, expectedNotes: [note])
    #expect(matcher.register(midiObservation(note: 60, seconds: 2, generation: 2)) == .insufficientEvidence)
    _ = matcher.register(midiObservation(note: 60, seconds: 2.1, isOn: false, generation: 2))
    #expect(matcher.register(midiObservation(note: 60, seconds: 2.2, generation: 2)) == .matched)
}

@Test
@MainActor
func midiMatcherDoesNotInventReleaseForIncapableSource() {
    let matcher = MIDIPracticeStepMatcher()
    let note = PracticeStepNote(midiNote: 60, staff: 1, handAssignment: rightHand)
    matcher.reset(stepIndex: 0, expectedNotes: [note])
    #expect(matcher.register(midiObservation(note: 60, seconds: 1, observesRelease: false)) == .matched)

    matcher.reset(stepIndex: 1, expectedNotes: [note])
    #expect(matcher.register(midiObservation(note: 60, seconds: 2, observesRelease: false)) == .matched)
}

private func midiObservation(
    note: Int,
    seconds: TimeInterval,
    isOn: Bool = true,
    observesRelease: Bool = true,
    generation: UInt64 = 1
) -> PerformanceObservation {
    var capabilities = PerformanceInputCapabilities.midi
    if observesRelease == false {
        capabilities = PerformanceInputCapabilities(
            pitch: capabilities.pitch,
            onset: capabilities.onset,
            release: .unavailable,
            velocity: capabilities.velocity,
            controllers: capabilities.controllers,
            polyphony: capabilities.polyphony,
            hand: capabilities.hand,
            finger: capabilities.finger,
            position: capabilities.position,
            confidence: capabilities.confidence
        )
    }
    let instant = PerformanceMonotonicInstant(seconds: seconds)
    return PerformanceObservation(
        source: .init(kind: .midi1, id: "test", generation: generation, capabilities: capabilities),
        timing: PerformanceClockReading(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: isOn
            ? .noteOn(note: note, velocity: .init(midi1: 96))
            : .noteOff(note: note, releaseVelocity: .init(midi1: 0)),
        channel: 1,
        group: 0
    )
}

private let rightHand = ScoreHandAssignment(hand: .right, provenance: .score)
