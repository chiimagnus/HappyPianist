import Foundation

struct ScorePerformancePlanID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct ScorePerformanceSourceIdentity: Codable, Equatable, Hashable, Sendable {
    let songID: UUID
    let scoreRevision: String
    let logicalInstrumentID: String
}

struct ScorePerformanceTickResolution: Codable, Equatable, Hashable, Sendable {
    let ticksPerQuarter: Int
}

struct ScorePerformancePlan: Codable, Equatable, Sendable {
    let id: ScorePerformancePlanID
    let sourceScoreIdentity: ScorePerformanceSourceIdentity
    let order: MusicXMLOrderSelection
    let resolution: ScorePerformanceTickResolution
    let noteEvents: [ScorePerformanceNoteEvent]
    let tempoEvents: [ScorePerformanceTempoEvent]
    let controllerEvents: [ScorePerformanceControllerEvent]
    let annotations: [ScorePerformanceAnnotation]
    let approximations: [ScorePerformanceApproximation]
}

struct ScorePerformanceNoteEventID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let performedNoteID: MusicXMLPerformedNoteID
    let generatedOrdinal: Int?

    var description: String {
        generatedOrdinal.map { "\(performedNoteID.description)#\($0)" } ?? performedNoteID.description
    }
}

enum ScorePerformanceNotePurpose: String, Codable, Equatable, Hashable, Sendable {
    case source
    case ornament
    case tremolo
    case glissando
}

struct ScorePerformanceWrittenPitch: Codable, Equatable, Hashable, Sendable {
    let step: String
    let octave: Int
    let alter: Double
    let accidentalToken: String?
}

struct ScorePerformanceVelocityResolution: Codable, Equatable, Sendable {
    let baseVelocity: Int
    let curveVelocity: Double?
    let articulationDelta: Int
    let unclampedVelocity: Int
    let velocity: UInt8
}

struct ScorePerformanceNoteEvent: Codable, Equatable, Sendable {
    let id: ScorePerformanceNoteEventID
    let sourceNoteID: MusicXMLSourceNoteID
    let performedNoteID: MusicXMLPerformedNoteID
    let contributingSourceNoteIDs: [MusicXMLSourceNoteID]
    let contributingPerformedNoteIDs: [MusicXMLPerformedNoteID]
    let purpose: ScorePerformanceNotePurpose
    let writtenOnTick: Int
    let writtenOffTick: Int
    let performedOnTick: Int
    let performedOffTick: Int
    let writtenPitch: ScorePerformanceWrittenPitch?
    let midiNote: Int
    let velocityResolution: ScorePerformanceVelocityResolution
    let staff: Int
    let voice: Int
    let handAssignment: ScoreHandAssignment
    let fingerings: [MusicXMLFingering]
    let timingProvenance: [ScorePerformanceProvenance]

    var velocity: UInt8 {
        velocityResolution.velocity
    }

    var performedOccurrenceIndex: Int {
        performedNoteID.occurrenceIndex
    }
}

struct ScorePerformanceTempoEvent: Codable, Equatable, Sendable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let quarterBPM: Double
    let endTick: Int?
    let endQuarterBPM: Double?
}

enum ScorePerformanceOutputCapabilityRequirement: String, Codable, Equatable, Hashable, Sendable {
    case continuousControlChange
}

struct ScorePerformanceControllerEvent: Codable, Equatable, Sendable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let controllerNumber: UInt8
    let value: UInt8
    let outputCapabilityRequirement: ScorePerformanceOutputCapabilityRequirement
}

enum ScorePerformanceAnnotationKind: String, Codable, Equatable, Hashable, Sendable {
    case pause
    case phrase
    case tempoWord
    case performanceNotation
}

struct ScorePerformanceAnnotation: Codable, Equatable, Sendable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let durationTicks: Int?
    let kind: ScorePerformanceAnnotationKind
    let text: String?
    let provenance: [ScorePerformanceProvenance]
}

enum ScorePerformanceProvenanceKind: String, Codable, Equatable, Hashable, Sendable {
    case score
    case performanceOffset
    case grace
    case arpeggio
    case interpretationProfile
    case performanceNotation
    case approximation
}

struct ScorePerformanceProvenance: Codable, Equatable, Hashable, Sendable {
    let kind: ScorePerformanceProvenanceKind
    let sourceIdentity: String?
    let detail: String?
}

enum ScorePerformanceApproximationScope: String, Codable, Equatable, Hashable, Sendable {
    case plan
    case note
    case tempo
    case controller
    case annotation
}

struct ScorePerformanceApproximation: Codable, Equatable, Hashable, Sendable {
    let scope: ScorePerformanceApproximationScope
    let eventIdentity: String?
    let reason: String
}
