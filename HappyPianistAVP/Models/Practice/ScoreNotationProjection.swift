import Foundation

struct ScoreNotationProjection: Equatable, Sendable {
    struct SourceNote: Equatable, Sendable {
        let id: MusicXMLSourceNoteID
        let writtenOnTick: Int
        let writtenDurationTicks: Int
        let writtenPitch: MusicXMLWrittenPitch?
        let midiNote: Int?
        let isRest: Bool
        let staff: Int
        let voice: Int
        let isGrace: Bool
        let tieStart: Bool
        let tieStop: Bool
        let articulations: Set<MusicXMLArticulation>
        let arpeggiate: MusicXMLArpeggiate?
        let fingeringText: String?
        let dotCount: Int
    }

    struct PerformedOccurrence: Equatable, Sendable {
        let id: ScorePerformanceNoteEventID
        let primarySourceNoteID: MusicXMLSourceNoteID
        let contributingSourceNoteIDs: [MusicXMLSourceNoteID]
        let performedOnTick: Int
        let performedOffTick: Int
        let midiNote: Int
        let handAssignment: ScoreHandAssignment
    }

    struct ActiveState: Equatable, Sendable {
        let occurrenceIDs: Set<ScorePerformanceNoteEventID>

        static let empty = ActiveState(occurrenceIDs: [])
    }

    let sourceNotes: [SourceNote]
    let performedOccurrences: [PerformedOccurrence]
    let activeState: ActiveState

    init(
        plan: ScorePerformancePlan,
        sourceScore: MusicXMLScore,
        activeState: ActiveState = .empty
    ) {
        sourceNotes = sourceScore.notes.compactMap { note in
            guard let sourceID = note.sourceID else { return nil }
            return SourceNote(
                id: sourceID,
                writtenOnTick: note.tick,
                writtenDurationTicks: note.durationTicks,
                writtenPitch: note.writtenPitch,
                midiNote: note.midiNote,
                isRest: note.isRest,
                staff: note.staff ?? 1,
                voice: note.voice ?? 1,
                isGrace: note.isGrace,
                tieStart: note.tieStart,
                tieStop: note.tieStop,
                articulations: note.articulations,
                arpeggiate: note.arpeggiate,
                fingeringText: note.fingeringText,
                dotCount: note.dotCount
            )
        }
        performedOccurrences = plan.noteEvents.map { event in
            PerformedOccurrence(
                id: event.id,
                primarySourceNoteID: event.sourceNoteID,
                contributingSourceNoteIDs: event.contributingSourceNoteIDs,
                performedOnTick: event.performedOnTick,
                performedOffTick: event.performedOffTick,
                midiNote: event.midiNote,
                handAssignment: event.handAssignment
            )
        }
        self.activeState = activeState
    }
}
