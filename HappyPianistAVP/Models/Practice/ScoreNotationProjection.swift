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
        let id: MusicXMLPerformedNoteID
        let sourceNoteID: MusicXMLSourceNoteID
        let performanceEventIDs: [ScorePerformanceNoteEventID]
        let writtenOnTick: Int
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
        let sourceNotesByID = Dictionary(grouping: sourceNotes, by: \.id)
            .compactMapValues { notes in notes.count == 1 ? notes[0] : nil }
        var occurrencesByID: [MusicXMLPerformedNoteID: PerformedOccurrence] = [:]

        for event in plan.noteEvents {
            guard let primarySource = sourceNotesByID[event.sourceNoteID] else { continue }
            for sourceNoteID in event.contributingSourceNoteIDs {
                guard let source = sourceNotesByID[sourceNoteID],
                      let performedNoteID = event.contributingPerformedNoteIDs.first(where: {
                          $0.sourceID == sourceNoteID
                      })
                else {
                    continue
                }
                let writtenOffset = source.writtenOnTick - primarySource.writtenOnTick
                if let existing = occurrencesByID[performedNoteID] {
                    let eventIDs = existing.performanceEventIDs.contains(event.id)
                        ? existing.performanceEventIDs
                        : existing.performanceEventIDs + [event.id]
                    occurrencesByID[performedNoteID] = PerformedOccurrence(
                        id: existing.id,
                        sourceNoteID: existing.sourceNoteID,
                        performanceEventIDs: eventIDs,
                        writtenOnTick: min(existing.writtenOnTick, event.writtenOnTick + writtenOffset),
                        performedOnTick: min(existing.performedOnTick, event.performedOnTick),
                        performedOffTick: max(existing.performedOffTick, event.performedOffTick),
                        midiNote: existing.midiNote,
                        handAssignment: existing.handAssignment
                    )
                } else {
                    occurrencesByID[performedNoteID] = PerformedOccurrence(
                        id: performedNoteID,
                        sourceNoteID: sourceNoteID,
                        performanceEventIDs: [event.id],
                        writtenOnTick: event.writtenOnTick + writtenOffset,
                        performedOnTick: event.performedOnTick,
                        performedOffTick: event.performedOffTick,
                        midiNote: event.midiNote,
                        handAssignment: event.handAssignment
                    )
                }
            }
        }
        performedOccurrences = occurrencesByID.values.sorted { lhs, rhs in
            if lhs.writtenOnTick != rhs.writtenOnTick { return lhs.writtenOnTick < rhs.writtenOnTick }
            return lhs.id.description < rhs.id.description
        }
        self.activeState = activeState
    }
}
