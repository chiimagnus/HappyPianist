import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func step3AudioRecognitionModeDoesNotContainMidiInput() {
    #expect(Step3AudioRecognitionMode.allCases == [.lowLatency, .stricter])
}

@Test
@MainActor
func singleNoteMatchesWhenExactMIDIWithOnset() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 1000)
    accumulator.resetForNewStep(generation: 7)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.9, isOnset: true, timestamp: now, generation: 7))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 7,
        at: now
    )

    #expect(result == .matched)
}

@Test
@MainActor
func singleNoteDoesNotMatchAdjacentSemitone() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 1000)
    accumulator.resetForNewStep(generation: 1)
    accumulator.register(evidence: makeEvent(midiNote: 61, confidence: 0.9, isOnset: true, timestamp: now, generation: 1))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 1,
        at: now
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func singleNoteReturnsInsufficientWhenConfidenceBelowThreshold() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 1000)
    accumulator.resetForNewStep(generation: 9)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.55, isOnset: true, timestamp: now, generation: 9))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 9,
        at: now
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func mismatchedGenerationEventsAreIgnored() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 1000)
    accumulator.resetForNewStep(generation: 10)
    accumulator.register(evidence: makeEvent(
        midiNote: 60,
        confidence: 0.95,
        isOnset: true,
        timestamp: now,
        generation: 11
    ))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 10,
        at: now
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func triadMajorityIsPartialEvidenceRatherThanMatch() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2000)
    accumulator.resetForNewStep(generation: 2)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.8, isOnset: true, timestamp: now, generation: 2))
    accumulator.register(evidence: makeEvent(
        midiNote: 64,
        confidence: 0.85,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.03),
        generation: 2
    ))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60, 64, 67],
        wrongCandidateMIDINotes: [61, 66],
        generation: 2,
        at: now.addingTimeInterval(0.04)
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func dyadRequiresBothExpectedNotes() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2000)
    accumulator.resetForNewStep(generation: 3)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.85, isOnset: true, timestamp: now, generation: 3))

    let insufficient = accumulator.evaluate(
        expectedMIDINotes: [60, 64],
        wrongCandidateMIDINotes: [],
        generation: 3,
        at: now.addingTimeInterval(0.02)
    )
    #expect(insufficient == .insufficientEvidence)

    accumulator.register(evidence: makeEvent(
        midiNote: 64,
        confidence: 0.84,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.04),
        generation: 3
    ))
    let matched = accumulator.evaluate(
        expectedMIDINotes: [60, 64],
        wrongCandidateMIDINotes: [],
        generation: 3,
        at: now.addingTimeInterval(0.05)
    )
    #expect(matched == .matched)
}

@Test
@MainActor
func strongWrongNoteBlocksMatch() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2100)
    accumulator.resetForNewStep(generation: 4)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.7, isOnset: true, timestamp: now, generation: 4))
    accumulator.register(evidence: makeEvent(
        midiNote: 61,
        confidence: 0.95,
        isWrongCandidate: true,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.01),
        generation: 4
    ))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [61],
        generation: 4,
        at: now.addingTimeInterval(0.02)
    )

    #expect(result == .wrongNote)
}

@Test
@MainActor
func expiredEventsAreIgnored() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2200)
    accumulator.resetForNewStep(generation: 5)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.9, isOnset: true, timestamp: now, generation: 5))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 5,
        at: now.addingTimeInterval(0.6)
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func resetForNewStepClearsOldGenerationEvents() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2300)
    accumulator.resetForNewStep(generation: 6)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.9, isOnset: true, timestamp: now, generation: 6))
    accumulator.resetForNewStep(generation: 7)

    let result = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 7,
        at: now.addingTimeInterval(0.01)
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func repeatedSameNoteNeedsRearmOrNewOnset() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2400)
    accumulator.resetForNewStep(generation: 8)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.9, isOnset: true, timestamp: now, generation: 8))

    let first = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 8,
        at: now
    )
    #expect(first == .matched)
    accumulator.markMatchedAndRequireRearm(expectedMIDINotes: [60], at: now)

    accumulator.register(
        evidence: makeEvent(
            midiNote: 60,
            confidence: 0.9,
            onsetScore: 1.0,
            isOnset: false,
            timestamp: now.addingTimeInterval(0.02),
            generation: 8
        )
    )
    let blocked = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 8,
        at: now.addingTimeInterval(0.02)
    )
    #expect(blocked == .insufficientEvidence)

    accumulator.register(evidence: makeEvent(
        midiNote: 60,
        confidence: 0.92,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.03),
        generation: 8
    ))
    let second = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 8,
        at: now.addingTimeInterval(0.03)
    )
    #expect(second == .matched)
}

@Test
@MainActor
func recognitionModesUseDifferentThresholds() {
    let lowLatency = AudioStepAttemptAccumulator()
    lowLatency.setMode(.lowLatency)
    let stricter = AudioStepAttemptAccumulator()
    stricter.setMode(.stricter)
    let now = Date(timeIntervalSince1970: 2500)

    lowLatency.resetForNewStep(generation: 11)
    lowLatency.register(evidence: makeEvent(midiNote: 60, confidence: 0.56, isOnset: true, timestamp: now, generation: 11))
    let lowLatencyResult = lowLatency.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 11,
        at: now
    )
    #expect(lowLatencyResult == .matched)

    stricter.resetForNewStep(generation: 11)
    stricter.register(evidence: makeEvent(midiNote: 60, confidence: 0.56, isOnset: true, timestamp: now, generation: 11))
    let stricterResult = stricter.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [],
        generation: 11,
        at: now
    )
    #expect(stricterResult == .insufficientEvidence)
}

@Test
@MainActor
func wrongNoteGraceWindowDoesNotRollbackImmediateMatch() {
    let accumulator = AudioStepAttemptAccumulator()
    accumulator.setMode(.lowLatency)
    let now = Date(timeIntervalSince1970: 2600)
    accumulator.resetForNewStep(generation: 12)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.6, isOnset: true, timestamp: now, generation: 12))

    let matched = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [61],
        generation: 12,
        at: now
    )
    #expect(matched == .matched)
    accumulator.markMatchedAndRequireRearm(expectedMIDINotes: [60], at: now)

    accumulator.register(evidence: makeEvent(
        midiNote: 61,
        confidence: 0.95,
        isWrongCandidate: true,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.08),
        generation: 12
    ))
    let graceResult = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [61],
        generation: 12,
        at: now.addingTimeInterval(0.08)
    )
    #expect(graceResult == .insufficientEvidence)

    accumulator.register(evidence: makeEvent(
        midiNote: 61,
        confidence: 0.95,
        isWrongCandidate: true,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.39),
        generation: 12
    ))
    let lateWrong = accumulator.evaluate(
        expectedMIDINotes: [60],
        wrongCandidateMIDINotes: [61],
        generation: 12,
        at: now.addingTimeInterval(0.40)
    )
    #expect(lateWrong == .wrongNote)
}

private func makeEvent(
    midiNote: Int,
    confidence: Double,
    isWrongCandidate: Bool = false,
    onsetScore: Double? = nil,
    isOnset: Bool,
    timestamp: Date,
    generation: Int
) -> TargetAudioEvidence {
    TargetAudioEvidence(
        targetMIDINotes: isWrongCandidate ? [] : [midiNote],
        targetConfidenceByMIDINote: isWrongCandidate ? [:] : [midiNote: confidence],
        wrongConfidenceByMIDINote: isWrongCandidate ? [midiNote: confidence] : [:],
        onsetScore: onsetScore ?? (isOnset ? 1.0 : 0.0),
        isOnset: isOnset,
        timestamp: timestamp,
        generation: generation
    )
}

@Test
@MainActor
func chordDoesNotCountLowConfidenceOnsetsTowardMajority() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2700)
    accumulator.resetForNewStep(generation: 13)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.9, isOnset: true, timestamp: now, generation: 13))
    accumulator.register(evidence: makeEvent(
        midiNote: 64,
        confidence: 0.1,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.02),
        generation: 13
    ))

    let result = accumulator.evaluate(
        expectedMIDINotes: [60, 64, 67],
        wrongCandidateMIDINotes: [],
        generation: 13,
        at: now.addingTimeInterval(0.03)
    )

    #expect(result == .insufficientEvidence)
}

@Test
@MainActor
func fourNoteChordMajorityRemainsPartialEvidence() {
    let accumulator = AudioStepAttemptAccumulator()
    let now = Date(timeIntervalSince1970: 2800)
    accumulator.resetForNewStep(generation: 14)
    accumulator.register(evidence: makeEvent(midiNote: 60, confidence: 0.9, isOnset: true, timestamp: now, generation: 14))
    accumulator.register(evidence: makeEvent(
        midiNote: 64,
        confidence: 0.9,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.01),
        generation: 14
    ))

    let twoOfFour = accumulator.evaluate(
        expectedMIDINotes: [60, 64, 67, 71],
        wrongCandidateMIDINotes: [],
        generation: 14,
        at: now.addingTimeInterval(0.02)
    )
    #expect(twoOfFour == .insufficientEvidence)

    accumulator.register(evidence: makeEvent(
        midiNote: 67,
        confidence: 0.9,
        isOnset: true,
        timestamp: now.addingTimeInterval(0.03),
        generation: 14
    ))
    let threeOfFour = accumulator.evaluate(
        expectedMIDINotes: [60, 64, 67, 71],
        wrongCandidateMIDINotes: [],
        generation: 14,
        at: now.addingTimeInterval(0.04)
    )
    #expect(threeOfFour == .insufficientEvidence)
}
