import Foundation

enum ScoreTimingReleasePolicy: String, Codable, Equatable, Sendable {
    case writtenDuration
    case performanceOffsets
    case graceStealPrevious
    case graceStealFollowing
    case graceStealPreviousAndFollowing
    case graceMakeTime
    case arpeggio
    case interpretationProfile
    case slurLegato
    case breathGap
}

enum ScoreGraceTimingKind: String, Codable, Equatable, Sendable {
    case stealPrevious
    case stealFollowing
    case stealPreviousAndFollowing
    case makeTime
}

enum ScoreTimingProvenance: Equatable, Sendable {
    case score
    case performanceOffset
    case grace(kind: ScoreGraceTimingKind)
    case arpeggio(numberToken: String, direction: MusicXMLArpeggiateDirection)
    case interpretationProfile(id: String)
    case performanceNotation(
        kind: MusicXMLPerformanceNotationKind,
        sourceID: MusicXMLPerformanceNotationSourceID?,
        profileID: String
    )
    case approximation(reason: String)
}

struct ScoreTimingEntry: Equatable, Sendable {
    let noteIndex: Int
    let sourceNoteID: MusicXMLSourceNoteID?
    let performedNoteID: MusicXMLPerformedNoteID?
    let writtenOnTick: Int
    let writtenOffTick: Int
    let performedOnTick: Int
    let performedOffTick: Int
    let onsetOffsetTicks: Int
    let releaseOffsetTicks: Int
    let releasePolicy: ScoreTimingReleasePolicy
    let provenance: [ScoreTimingProvenance]
}


enum ScoreGeneratedNotePurpose: String, Codable, Equatable, Sendable {
    case ornament
    case tremolo
    case glissando
}

struct ScoreGeneratedNoteEvent: Equatable, Sendable {
    let sourceNoteIndices: [Int]
    let sourceNotationID: MusicXMLPerformanceNotationSourceID?
    let notationKind: MusicXMLPerformanceNotationKind
    let purpose: ScoreGeneratedNotePurpose
    let ordinal: Int
    let midiNote: Int
    let onTick: Int
    let offTick: Int
    let interpretationProfileID: String
}

enum ScorePerformanceNotationResolutionStatus: Equatable, Sendable {
    case generated
    case unsupported(reason: String)
}

struct ScorePerformanceNotationResolution: Equatable, Sendable {
    let sourceNotationID: MusicXMLPerformanceNotationSourceID?
    let notationKind: MusicXMLPerformanceNotationKind
    let sourceNoteIndices: [Int]
    let replacesSourceNoteIndices: [Int]
    let status: ScorePerformanceNotationResolutionStatus
    let interpretationProfileID: String
}

enum ScoreTimingDirectiveKind: String, Codable, Equatable, Sendable {
    case caesuraPause
}

struct ScoreTimingDirective: Equatable, Sendable {
    let kind: ScoreTimingDirectiveKind
    let tick: Int
    let durationTicks: Int
    let sourceNotationID: MusicXMLPerformanceNotationSourceID?
    let interpretationProfileID: String
}

struct ScoreTimingSchedule: Equatable, Sendable {
    let entries: [ScoreTimingEntry]
    let directives: [ScoreTimingDirective]
    let generatedNotes: [ScoreGeneratedNoteEvent]
    let notationResolutions: [ScorePerformanceNotationResolution]

    init(
        entries: [ScoreTimingEntry],
        directives: [ScoreTimingDirective] = [],
        generatedNotes: [ScoreGeneratedNoteEvent] = [],
        notationResolutions: [ScorePerformanceNotationResolution] = []
    ) {
        self.entries = entries
        self.directives = directives
        self.generatedNotes = generatedNotes
        self.notationResolutions = notationResolutions
    }

    subscript(noteIndex: Int) -> ScoreTimingEntry {
        entries[noteIndex]
    }
}
