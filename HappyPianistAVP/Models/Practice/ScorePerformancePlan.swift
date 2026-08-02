import Foundation
import MusicXML

struct ScorePerformancePlanID: Codable, Equatable, Hashable {
    let rawValue: String
}

struct ScorePerformanceSourceIdentity: Codable, Equatable, Hashable {
    let songID: UUID
    let scoreRevision: String
    let logicalInstrumentID: String
}

struct ScorePerformanceTickResolution: Codable, Equatable, Hashable {
    let ticksPerQuarter: Int
}

struct ScorePerformancePlan: Codable, Equatable {
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

struct ScorePerformanceNoteEventID: Codable, Equatable, Hashable, CustomStringConvertible {
    let performedNoteID: MusicXMLPerformedNoteID
    let generatedOrdinal: Int?

    var description: String {
        generatedOrdinal.map { "\(performedNoteID.description)#\($0)" } ?? performedNoteID.description
    }
}

enum ScorePerformanceNotePurpose: String, Codable, Equatable, Hashable {
    case source
    case ornament
    case tremolo
    case glissando
}

struct ScorePerformanceWrittenPitch: Codable, Equatable, Hashable {
    let step: String
    let octave: Int
    let alter: Double
    let accidentalToken: String?
}

struct ScorePerformanceVelocityResolution: Codable, Equatable {
    let baseVelocity: Int
    let curveVelocity: Double?
    let articulationDelta: Int
    let unclampedVelocity: Int
    let velocity: UInt8
    let usesGenericDynamicBaseline: Bool
}

struct ScorePerformanceNoteEvent: Codable, Equatable {
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

struct ScorePerformanceTempoEvent: Codable, Equatable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let quarterBPM: Double
    let endTick: Int?
    let endQuarterBPM: Double?
}

enum ScorePerformanceOutputCapabilityRequirement: String, Codable, Equatable, Hashable {
    case continuousControlChange
}

struct ScorePerformanceControllerEvent: Codable, Equatable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let controllerNumber: UInt8
    let value: UInt8
    let outputCapabilityRequirement: ScorePerformanceOutputCapabilityRequirement
}

enum ScorePerformanceAnnotationKind: String, Codable, Equatable, Hashable {
    case pause
    case phrase
    case tempoWord
    case performanceNotation
}

struct ScorePerformanceAnnotation: Codable, Equatable {
    let sourceDirectionID: MusicXMLDirectionSourceID?
    let performedOccurrenceIndex: Int
    let tick: Int
    let durationTicks: Int?
    let kind: ScorePerformanceAnnotationKind
    let text: String?
    let provenance: [ScorePerformanceProvenance]
}

enum ScorePerformanceProvenanceKind: String, Codable, Equatable, Hashable {
    case score
    case performanceOffset
    case grace
    case arpeggio
    case interpretationProfile
    case performanceNotation
    case approximation
}

struct ScorePerformanceProvenance: Codable, Equatable, Hashable {
    let kind: ScorePerformanceProvenanceKind
    let sourceIdentity: String?
    let detail: String?
}

enum ScorePerformanceApproximationScope: String, Codable, Equatable, Hashable {
    case plan
    case note
    case tempo
    case controller
    case annotation
}

struct ScorePerformanceApproximation: Codable, Equatable, Hashable {
    let scope: ScorePerformanceApproximationScope
    let eventIdentity: String?
    let reason: String
}
