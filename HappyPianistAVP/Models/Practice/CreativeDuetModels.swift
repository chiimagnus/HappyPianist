import Foundation

/// Observed musical material supplied to an AI creative-duet backend.
///
/// This deliberately contains no `ScorePerformancePlan`, reference performance,
/// assessment target, or teacher fact. It is only the user's observable input.
struct CreativeDuetPhrase: Equatable, Sendable {
    let events: [ImprovEvent]
    let provenance: CreativeDuetPhraseProvenance
}

struct CreativeDuetPhraseProvenance: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case observedLiveInput
        case recording
    }

    enum Capability: String, Hashable, Sendable {
        case pitch
        case onset
        case velocity
        case duration
        case controller
    }

    let source: Source
    let observedCapabilities: Set<Capability>
    let approximations: Set<String>

    static func observed(from events: [ImprovEvent]) -> Self {
        var capabilities: Set<Capability> = [.onset]

        for event in events {
            switch event.type {
            case .note:
                if event.note != nil { capabilities.insert(.pitch) }
                if event.velocity != nil { capabilities.insert(.velocity) }
                if event.duration != nil { capabilities.insert(.duration) }
            case .cc:
                if event.controller != nil, event.value != nil {
                    capabilities.insert(.controller)
                }
            }
        }

        return Self(
            source: .observedLiveInput,
            observedCapabilities: capabilities,
            approximations: []
        )
    }
}

/// Identifies one cancellable creative generation, never a score-derived target.
struct CreativeDuetGeneration: Equatable, Sendable {
    let requestID: Int
    let activationID: Int
    let seed: UInt64
    let sessionID: String
    let parameters: ImprovGenerateParams
}

struct CreativeDuetResponse: Equatable, Sendable {
    let schedule: [PracticeSequencerMIDIEvent]
    let provider: ImprovBackendKind
    let generation: CreativeDuetGeneration
    let provenance: CreativeDuetResponseProvenance
}

enum CreativeDuetResponseProvenance: Equatable, Sendable {
    case backendGenerated(latencyMS: Int?)
}
