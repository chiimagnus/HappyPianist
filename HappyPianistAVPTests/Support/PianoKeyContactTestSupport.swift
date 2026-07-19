import Foundation
@testable import HappyPianistAVP

func makeTestKeyContactObservation(
    midiNote: Int,
    phase: PianoKeyContactObservation.Phase,
    hand: TrackedHandSide = .right,
    finger: TrackedFinger = .index,
    sequence: UInt64 = 1,
    timestamp: PerformanceMonotonicInstant = .init(seconds: 1),
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
        calibrationID: calibrationID
    )
}

func makeTestKeyContactObservations(
    activeMIDINotes: Set<Int> = [],
    startedMIDINotes: Set<Int> = [],
    endedMIDINotes: Set<Int> = [],
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
