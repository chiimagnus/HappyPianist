import Foundation

/// Converts the app's canonical, capability-aware observation into the subset
/// that an AI creative-duet prompt can represent.
struct PerformanceObservationPhraseAdapter {
    struct PhraseEvent: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case noteOn(midi: Int, velocity: Int?)
            case noteOff(midi: Int)
            case controlChange(controller: Int, value: Int)
            case allNotesOff
        }

        let observationID: UUID
        let source: PerformanceObservation.Source
        let timestamp: PerformanceMonotonicInstant
        let timingProvenance: PerformanceClockCorrectionProvenance
        let kind: Kind

        var provenance: CreativeDuetPhraseProvenance.Observation {
            .init(
                id: observationID,
                source: source,
                timingProvenance: timingProvenance
            )
        }

        var sustainObservation: CreativeDuetPhraseProvenance.Observation.SustainObservation {
            provenance.sustainObservation
        }
    }

    func phraseEvent(from observation: PerformanceObservation) -> PhraseEvent? {
        let makeEvent: (PhraseEvent.Kind) -> PhraseEvent = { kind in
            PhraseEvent(
                observationID: observation.id,
                source: observation.source,
                timestamp: observation.alignmentTimestamp,
                timingProvenance: observation.timing.provenance,
                kind: kind
            )
        }

        switch observation.event {
        case let .noteOn(note, velocity):
            return makeEvent(.noteOn(
                midi: clamp7Bit(note),
                velocity: (velocity ?? observation.onsetVelocity).map(midi7Bit)
            ))
        case let .noteOff(note, _):
            return makeEvent(.noteOff(midi: clamp7Bit(note)))
        case let .controller(.controlChange(number, value)):
            if number == 120 || number == 123 {
                return makeEvent(.allNotesOff)
            }
            return makeEvent(.controlChange(controller: clamp7Bit(number), value: midi7Bit(value)))
        case .controller, .targetAudioDetection:
            return nil
        case let .contact(_, keyCandidate, phase):
            guard let keyCandidate else { return nil }
            switch phase {
            case .started:
                return makeEvent(.noteOn(
                    midi: clamp7Bit(keyCandidate),
                    velocity: observation.onsetVelocity.map(midi7Bit)
                ))
            case .ended:
                return makeEvent(.noteOff(midi: clamp7Bit(keyCandidate)))
            case .held:
                return nil
            }
        }
    }

    private func midi7Bit(_ value: PerformanceObservation.NormalizedValue) -> Int {
        MIDI2ValueMapping.value32To7Bit(value.rawValue)
    }

    private func clamp7Bit(_ value: Int) -> Int {
        min(127, max(0, value))
    }
}
