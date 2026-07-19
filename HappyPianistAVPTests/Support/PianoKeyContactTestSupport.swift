import Foundation
@testable import HappyPianistAVP

@MainActor
final class TestKeyContactDetector: KeyContactDetectingProtocol {
    private var resultIndex = 0
    private let results: [[PianoKeyContactObservation]]

    init(results: [[PianoKeyContactObservation]]) {
        self.results = results
    }

    func reset() {
        resultIndex = 0
    }

    func detect(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry,
        at _: PerformanceMonotonicInstant
    ) -> [PianoKeyContactObservation] {
        guard results.indices.contains(resultIndex) else { return [] }
        defer { resultIndex += 1 }
        return results[resultIndex]
    }
}

func makeTestKeyContactObservation(
    midiNote: Int,
    phase: PianoKeyContactObservation.Phase,
    hand: TrackedHandSide = .right,
    finger: TrackedFinger = .index,
    sequence: UInt64 = 1,
    timestamp: PerformanceMonotonicInstant = .init(seconds: 1),
    resolvedVelocity: UInt8? = 90,
    calibrationID: UUID = UUID()
) -> PianoKeyContactObservation {
    PianoKeyContactObservation(
        id: PianoKeyContactID(finger: TrackedFingerID(hand: hand, finger: finger), sequence: sequence),
        phase: phase,
        keyCandidate: .exact(midiNote),
        timestamp: timestamp,
        confidence: 1,
        worldPosition: .zero,
        planeDistanceMeters: 0,
        normalVelocityMetersPerSecond: nil,
        resolvedVelocity: resolvedVelocity,
        calibrationID: calibrationID
    )
}

func makeTestKeyContactObservations(
    activeMIDINotes: Set<Int> = [],
    startedMIDINotes: Set<Int> = [],
    endedMIDINotes: Set<Int> = [],
    startedVelocity: UInt8? = 90,
    timestamp: PerformanceMonotonicInstant = .init(seconds: 1)
) -> [PianoKeyContactObservation] {
    let fingerIDs = TrackedHandSide.allCases.flatMap { hand in
        TrackedFinger.allCases.map { TrackedFingerID(hand: hand, finger: $0) }
    }
    let calibrationID = UUID()
    var sequence: UInt64 = 0

    func makeObservation(note: Int, phase: PianoKeyContactObservation.Phase) -> PianoKeyContactObservation {
        sequence &+= 1
        let fingerID = fingerIDs[Int(sequence - 1) % fingerIDs.count]
        return makeTestKeyContactObservation(
            midiNote: note,
            phase: phase,
            hand: fingerID.hand,
            finger: fingerID.finger,
            sequence: sequence,
            timestamp: timestamp,
            resolvedVelocity: phase == .started ? startedVelocity : nil,
            calibrationID: calibrationID
        )
    }

    let active = activeMIDINotes.sorted().map { note in
        makeObservation(note: note, phase: startedMIDINotes.contains(note) ? .started : .held)
    }
    let startsWithoutActive = startedMIDINotes.subtracting(activeMIDINotes).sorted().map {
        makeObservation(note: $0, phase: .started)
    }
    let ended = endedMIDINotes.sorted().map { makeObservation(note: $0, phase: .ended) }
    return active + startsWithoutActive + ended
}
