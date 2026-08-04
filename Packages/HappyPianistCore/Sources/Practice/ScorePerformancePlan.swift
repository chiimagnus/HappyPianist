import Foundation
import MusicXML

public struct ScorePerformancePlanID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ScorePerformanceSourceIdentity: Codable, Equatable, Hashable, Sendable {
    public let songID: UUID
    public let scoreRevision: String
    public let logicalInstrumentID: String

    public init(songID: UUID, scoreRevision: String, logicalInstrumentID: String) {
        self.songID = songID
        self.scoreRevision = scoreRevision
        self.logicalInstrumentID = logicalInstrumentID
    }
}

public struct ScorePerformanceTickResolution: Codable, Equatable, Hashable, Sendable {
    public let ticksPerQuarter: Int

    public init(ticksPerQuarter: Int) {
        self.ticksPerQuarter = ticksPerQuarter
    }
}

public struct ScorePerformancePlan: Codable, Equatable, Sendable {
    public let id: ScorePerformancePlanID
    public let sourceScoreIdentity: ScorePerformanceSourceIdentity
    public let order: MusicXMLOrderSelection
    public let resolution: ScorePerformanceTickResolution
    public let noteEvents: [ScorePerformanceNoteEvent]
    public let tempoEvents: [ScorePerformanceTempoEvent]
    public let controllerEvents: [ScorePerformanceControllerEvent]
    public let annotations: [ScorePerformanceAnnotation]
    public let approximations: [ScorePerformanceApproximation]

    public init(
        id: ScorePerformancePlanID,
        sourceScoreIdentity: ScorePerformanceSourceIdentity,
        order: MusicXMLOrderSelection,
        resolution: ScorePerformanceTickResolution,
        noteEvents: [ScorePerformanceNoteEvent],
        tempoEvents: [ScorePerformanceTempoEvent],
        controllerEvents: [ScorePerformanceControllerEvent],
        annotations: [ScorePerformanceAnnotation],
        approximations: [ScorePerformanceApproximation]
    ) {
        self.id = id
        self.sourceScoreIdentity = sourceScoreIdentity
        self.order = order
        self.resolution = resolution
        self.noteEvents = noteEvents
        self.tempoEvents = tempoEvents
        self.controllerEvents = controllerEvents
        self.annotations = annotations
        self.approximations = approximations
    }
}

public struct ScorePerformanceNoteEventID: Codable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let performedNoteID: MusicXMLPerformedNoteID
    public let generatedOrdinal: Int?

    public var description: String {
        generatedOrdinal.map { "\(performedNoteID.description)#\($0)" } ?? performedNoteID.description
    }
    public init(performedNoteID: MusicXMLPerformedNoteID, generatedOrdinal: Int?) {
        self.performedNoteID = performedNoteID
        self.generatedOrdinal = generatedOrdinal
    }
}

public enum ScorePerformanceNotePurpose: String, Codable, Equatable, Hashable, Sendable {
    case source
    case ornament
    case tremolo
    case glissando
}

public struct ScorePerformanceWrittenPitch: Codable, Equatable, Hashable, Sendable {
    public let step: String
    public let octave: Int
    public let alter: Double
    public let accidentalToken: String?

    public init(step: String, octave: Int, alter: Double, accidentalToken: String?) {
        self.step = step
        self.octave = octave
        self.alter = alter
        self.accidentalToken = accidentalToken
    }
}

public struct ScorePerformanceVelocityResolution: Codable, Equatable, Sendable {
    public let baseVelocity: Int
    public let curveVelocity: Double?
    public let articulationDelta: Int
    public let unclampedVelocity: Int
    public let velocity: UInt8
    public let usesGenericDynamicBaseline: Bool

    public init(
        baseVelocity: Int,
        curveVelocity: Double?,
        articulationDelta: Int,
        unclampedVelocity: Int,
        velocity: UInt8,
        usesGenericDynamicBaseline: Bool
    ) {
        self.baseVelocity = baseVelocity
        self.curveVelocity = curveVelocity
        self.articulationDelta = articulationDelta
        self.unclampedVelocity = unclampedVelocity
        self.velocity = velocity
        self.usesGenericDynamicBaseline = usesGenericDynamicBaseline
    }
}

public struct ScorePerformanceNoteEvent: Codable, Equatable, Sendable {
    public let id: ScorePerformanceNoteEventID
    public let sourceNoteID: MusicXMLSourceNoteID
    public let performedNoteID: MusicXMLPerformedNoteID
    public let contributingSourceNoteIDs: [MusicXMLSourceNoteID]
    public let contributingPerformedNoteIDs: [MusicXMLPerformedNoteID]
    public let purpose: ScorePerformanceNotePurpose
    public let writtenOnTick: Int
    public let writtenOffTick: Int
    public let performedOnTick: Int
    public let performedOffTick: Int
    public let writtenPitch: ScorePerformanceWrittenPitch?
    public let midiNote: Int
    public let velocityResolution: ScorePerformanceVelocityResolution
    public let staff: Int
    public let voice: Int
    public let handAssignment: ScoreHandAssignment
    public let fingerings: [MusicXMLFingering]
    public let timingProvenance: [ScorePerformanceProvenance]

    public var velocity: UInt8 {
        velocityResolution.velocity
    }

    public var performedOccurrenceIndex: Int {
        performedNoteID.occurrenceIndex
    }
    public init(
        id: ScorePerformanceNoteEventID,
        sourceNoteID: MusicXMLSourceNoteID,
        performedNoteID: MusicXMLPerformedNoteID,
        contributingSourceNoteIDs: [MusicXMLSourceNoteID],
        contributingPerformedNoteIDs: [MusicXMLPerformedNoteID],
        purpose: ScorePerformanceNotePurpose,
        writtenOnTick: Int,
        writtenOffTick: Int,
        performedOnTick: Int,
        performedOffTick: Int,
        writtenPitch: ScorePerformanceWrittenPitch?,
        midiNote: Int,
        velocityResolution: ScorePerformanceVelocityResolution,
        staff: Int,
        voice: Int,
        handAssignment: ScoreHandAssignment,
        fingerings: [MusicXMLFingering],
        timingProvenance: [ScorePerformanceProvenance]
    ) {
        self.id = id
        self.sourceNoteID = sourceNoteID
        self.performedNoteID = performedNoteID
        self.contributingSourceNoteIDs = contributingSourceNoteIDs
        self.contributingPerformedNoteIDs = contributingPerformedNoteIDs
        self.purpose = purpose
        self.writtenOnTick = writtenOnTick
        self.writtenOffTick = writtenOffTick
        self.performedOnTick = performedOnTick
        self.performedOffTick = performedOffTick
        self.writtenPitch = writtenPitch
        self.midiNote = midiNote
        self.velocityResolution = velocityResolution
        self.staff = staff
        self.voice = voice
        self.handAssignment = handAssignment
        self.fingerings = fingerings
        self.timingProvenance = timingProvenance
    }
}

public enum ScorePerformanceOutputCapabilityRequirement: String, Codable, Equatable, Hashable, Sendable {
    case continuousControlChange
}

public struct ScorePerformanceControllerEvent: Codable, Equatable, Sendable {
    public let sourceDirectionID: MusicXMLDirectionSourceID?
    public let performedOccurrenceIndex: Int
    public let tick: Int
    public let controllerNumber: UInt8
    public let value: UInt8
    public let outputCapabilityRequirement: ScorePerformanceOutputCapabilityRequirement

    public init(
        sourceDirectionID: MusicXMLDirectionSourceID?,
        performedOccurrenceIndex: Int,
        tick: Int,
        controllerNumber: UInt8,
        value: UInt8,
        outputCapabilityRequirement: ScorePerformanceOutputCapabilityRequirement
    ) {
        self.sourceDirectionID = sourceDirectionID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.controllerNumber = controllerNumber
        self.value = value
        self.outputCapabilityRequirement = outputCapabilityRequirement
    }
}

public enum ScorePerformanceAnnotationKind: String, Codable, Equatable, Hashable, Sendable {
    case pause
    case phrase
    case tempoWord
    case performanceNotation
}

public struct ScorePerformanceAnnotation: Codable, Equatable, Sendable {
    public let sourceDirectionID: MusicXMLDirectionSourceID?
    public let performedOccurrenceIndex: Int
    public let tick: Int
    public let durationTicks: Int?
    public let kind: ScorePerformanceAnnotationKind
    public let text: String?
    public let provenance: [ScorePerformanceProvenance]

    public init(
        sourceDirectionID: MusicXMLDirectionSourceID?,
        performedOccurrenceIndex: Int,
        tick: Int,
        durationTicks: Int?,
        kind: ScorePerformanceAnnotationKind,
        text: String?,
        provenance: [ScorePerformanceProvenance]
    ) {
        self.sourceDirectionID = sourceDirectionID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.durationTicks = durationTicks
        self.kind = kind
        self.text = text
        self.provenance = provenance
    }
}

public enum ScorePerformanceProvenanceKind: String, Codable, Equatable, Hashable, Sendable {
    case score
    case performanceOffset
    case grace
    case arpeggio
    case interpretationProfile
    case performanceNotation
    case approximation
}

public struct ScorePerformanceProvenance: Codable, Equatable, Hashable, Sendable {
    public let kind: ScorePerformanceProvenanceKind
    public let sourceIdentity: String?
    public let detail: String?

    public init(kind: ScorePerformanceProvenanceKind, sourceIdentity: String?, detail: String?) {
        self.kind = kind
        self.sourceIdentity = sourceIdentity
        self.detail = detail
    }
}

public enum ScorePerformanceApproximationScope: String, Codable, Equatable, Hashable, Sendable {
    case plan
    case note
    case tempo
    case controller
    case annotation
}

public struct ScorePerformanceApproximation: Codable, Equatable, Hashable, Sendable {
    public let scope: ScorePerformanceApproximationScope
    public let eventIdentity: String?
    public let reason: String

    public init(scope: ScorePerformanceApproximationScope, eventIdentity: String?, reason: String) {
        self.scope = scope
        self.eventIdentity = eventIdentity
        self.reason = reason
    }
}
