import Foundation

enum ScoreTimingReleasePolicy: String, Codable, Equatable, Sendable {
    case writtenDuration
    case performanceOffsets
}

enum ScoreTimingProvenance: Equatable, Sendable {
    case score
    case performanceOffset
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
