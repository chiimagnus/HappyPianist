import Foundation

struct PianoKeyContactPerformanceObservationAdapter: Sendable {
    func observation(
        from contact: PianoKeyContactObservation,
        sourceKind: PerformanceObservation.Source.Kind,
        generation: UInt64
    ) -> PerformanceObservation {
        let phase: PerformanceObservation.ContactPhase = switch contact.phase {
        case .started: .started
        case .held: .held
        case .ended: .ended
        }
        return PerformanceObservation(
            id: contact.observationID,
            source: PerformanceObservation.Source(
                kind: sourceKind,
                id: sourceKind == .virtualPianoContact
                    ? "virtual-piano-key-contact"
                    : "real-piano-key-contact",
                generation: generation,
                capabilities: .handContact
            ),
            timing: PerformanceClockReading(
                host: contact.timestamp,
                source: nil,
                correctedHost: contact.timestamp,
                mapping: nil,
                provenance: .hostOnly
            ),
            event: .contact(
                id: "\(contact.hand)-\(contact.finger)-\(contact.id.sequence)",
                keyCandidate: contact.keyCandidate.exactMIDINote,
                phase: phase
            ),
            onsetVelocity: contact.resolvedVelocity.map { .init(midi1: Int($0)) },
            hand: contact.hand.scoreHand,
            finger: Int(contact.finger.rawValue) + 1,
            confidence: Double(contact.confidence),
            calibrationReference: contact.calibrationID.uuidString
        )
    }
}

extension TrackedHandSide {
    var scoreHand: ScoreHand {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}
