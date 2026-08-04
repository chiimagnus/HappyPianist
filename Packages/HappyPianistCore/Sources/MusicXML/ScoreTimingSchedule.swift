import Foundation


public enum ScoreTimingReleasePolicy: String, Codable, Equatable {
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

public enum ScoreGraceTimingKind: String, Codable, Equatable {
    case stealPrevious
    case stealFollowing
    case stealPreviousAndFollowing
    case makeTime
}

public enum ScoreTimingProvenance: Equatable {
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

public struct ScoreTimingEntry: Equatable {
    public let noteIndex: Int
    public let sourceNoteID: MusicXMLSourceNoteID?
    public let performedNoteID: MusicXMLPerformedNoteID?
    public let writtenOnTick: Int
    public let writtenOffTick: Int
    public let performedOnTick: Int
    public let performedOffTick: Int
    public let onsetOffsetTicks: Int
    public let releaseOffsetTicks: Int
    public let releasePolicy: ScoreTimingReleasePolicy
    public let provenance: [ScoreTimingProvenance]
}

public enum ScoreGeneratedNotePurpose: String, Codable, Equatable {
    case ornament
    case tremolo
    case glissando
}

public struct ScoreGeneratedNoteEvent: Equatable {
    public let sourceNoteIndices: [Int]
    public let sourceNotationID: MusicXMLPerformanceNotationSourceID?
    public let notationKind: MusicXMLPerformanceNotationKind
    public let purpose: ScoreGeneratedNotePurpose
    public let ordinal: Int
    public let midiNote: Int
    public let onTick: Int
    public let offTick: Int
    public let interpretationProfileID: String
}

public enum ScorePerformanceNotationResolutionStatus: Equatable {
    case generated
    case unsupported(reason: String)
}

public struct ScorePerformanceNotationResolution: Equatable {
    public let sourceNotationID: MusicXMLPerformanceNotationSourceID?
    public let notationKind: MusicXMLPerformanceNotationKind
    public let sourceNoteIndices: [Int]
    public let replacesSourceNoteIndices: [Int]
    public let status: ScorePerformanceNotationResolutionStatus
    public let interpretationProfileID: String
}

public enum ScoreTimingDirectiveKind: String, Codable, Equatable {
    case caesuraPause
}

public struct ScoreTimingDirective: Equatable {
    public let kind: ScoreTimingDirectiveKind
    public let tick: Int
    public let durationTicks: Int
    public let sourceNotationID: MusicXMLPerformanceNotationSourceID?
    public let interpretationProfileID: String
}

public struct ScoreTimingSchedule: Equatable {
    public let entries: [ScoreTimingEntry]
    public let directives: [ScoreTimingDirective]
    public let generatedNotes: [ScoreGeneratedNoteEvent]
    public let notationResolutions: [ScorePerformanceNotationResolution]

    public init(
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

    public subscript(noteIndex: Int) -> ScoreTimingEntry {
        entries[noteIndex]
    }
}
