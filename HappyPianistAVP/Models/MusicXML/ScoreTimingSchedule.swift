import Foundation

enum ScoreTimingReleasePolicy: String, Codable, Equatable, Sendable {
    case writtenDuration
    case performanceOffsets
    case graceStealPrevious
    case graceStealFollowing
    case graceStealPreviousAndFollowing
    case graceMakeTime
    case arpeggio
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

struct ScoreTimingSchedule: Equatable, Sendable {
    let entries: [ScoreTimingEntry]

    subscript(noteIndex: Int) -> ScoreTimingEntry {
        entries[noteIndex]
    }
}
