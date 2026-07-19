import Foundation

struct ScoreNotationProjection: Equatable, Sendable {
    struct TransposeFact: Equatable, Sendable {
        let diatonic: Int?
        let chromatic: Int
        let octaveChange: Int
        let isDouble: Bool
    }

    struct OctaveShiftFact: Equatable, Sendable {
        let kind: MusicXMLOctaveShiftKind
        let size: Int
        let numberToken: String?
    }

    struct SourceNote: Equatable, Sendable {
        let id: MusicXMLSourceNoteID
        let writtenOnTick: Int
        let writtenDurationTicks: Int
        let writtenPitch: MusicXMLWrittenPitch?
        let writtenRhythm: MusicXMLWrittenRhythm?
        let midiNote: Int?
        let isRest: Bool
        let isPrintObjectVisible: Bool
        let staff: Int
        let voice: Int
        let isGrace: Bool
        let ties: [MusicXMLTie]
        let slurs: [MusicXMLSlur]
        let tuplets: [MusicXMLTuplet]
        let articulations: Set<MusicXMLArticulation>
        let arpeggiate: MusicXMLArpeggiate?
        let fingeringText: String?
        let keySignatureFifths: Int
        let transpose: TransposeFact?
        let octaveShifts: [OctaveShiftFact]
    }

    struct PerformedOccurrence: Equatable, Sendable {
        let id: MusicXMLPerformedNoteID
        let sourceNoteID: MusicXMLSourceNoteID
        let performanceEventIDs: [ScorePerformanceNoteEventID]
        let writtenOnTick: Int
        let performedOnTick: Int
        let performedOffTick: Int
        let handAssignment: ScoreHandAssignment
    }

    struct Overlay: Equatable, Sendable {
        let activeEventIDs: Set<ScorePerformanceNoteEventID>
        let activeTickRange: Range<Int>?

        static let empty = Overlay(activeEventIDs: [], activeTickRange: nil)
    }

    let sourceNotes: [SourceNote]
    let performedOccurrences: [PerformedOccurrence]

    static let empty = ScoreNotationProjection(
        sourceNotes: [],
        performedOccurrences: []
    )

    init(
        plan: ScorePerformancePlan,
        sourceScore: MusicXMLScore
    ) {
        sourceNotes = sourceScore.notes.compactMap { note in
            guard let sourceID = note.sourceID else { return nil }
            return SourceNote(
                id: sourceID,
                writtenOnTick: note.tick,
                writtenDurationTicks: note.durationTicks,
                writtenPitch: note.writtenPitch,
                writtenRhythm: note.writtenRhythm,
                midiNote: note.midiNote,
                isRest: note.isRest,
                isPrintObjectVisible: note.isPrintObjectVisible,
                staff: note.staff ?? 1,
                voice: note.voice ?? 1,
                isGrace: note.isGrace,
                ties: note.ties,
                slurs: note.slurs,
                tuplets: note.tuplets,
                articulations: note.articulations,
                arpeggiate: note.arpeggiate,
                fingeringText: note.fingeringText,
                keySignatureFifths: Self.keySignatureFifths(for: note, in: sourceScore),
                transpose: Self.transposeFact(for: note, in: sourceScore),
                octaveShifts: Self.octaveShiftFacts(for: note, in: sourceScore)
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
                        handAssignment: event.handAssignment
                    )
                }
            }
        }
        let linkedSourceNoteIDs = Set(occurrencesByID.values.map(\.sourceNoteID))
        for source in sourceNotes where linkedSourceNoteIDs.contains(source.id) == false {
            let performedID = MusicXMLPerformedNoteID(sourceID: source.id, occurrenceIndex: 0)
            occurrencesByID[performedID] = PerformedOccurrence(
                id: performedID,
                sourceNoteID: source.id,
                performanceEventIDs: [],
                writtenOnTick: source.writtenOnTick,
                performedOnTick: source.writtenOnTick,
                performedOffTick: source.writtenOnTick + source.writtenDurationTicks,
                handAssignment: .unknown
            )
        }
        performedOccurrences = occurrencesByID.values.sorted { lhs, rhs in
            if lhs.writtenOnTick != rhs.writtenOnTick { return lhs.writtenOnTick < rhs.writtenOnTick }
            return lhs.id.description < rhs.id.description
        }
    }

    private static func keySignatureFifths(for note: MusicXMLNoteEvent, in score: MusicXMLScore) -> Int {
        score.keySignatureEvents
            .filter { $0.tick <= note.tick && scope($0.scope, matches: note) }
            .max { lhs, rhs in
                lhs.tick == rhs.tick
                    ? scopeSpecificity(lhs.scope) < scopeSpecificity(rhs.scope)
                    : lhs.tick < rhs.tick
            }?
            .fifths ?? 0
    }

    private static func transposeFact(for note: MusicXMLNoteEvent, in score: MusicXMLScore) -> TransposeFact? {
        score.transposeEvents
            .filter { $0.tick <= note.tick && scope($0.scope, matches: note) }
            .max { lhs, rhs in
                lhs.tick == rhs.tick
                    ? scopeSpecificity(lhs.scope) < scopeSpecificity(rhs.scope)
                    : lhs.tick < rhs.tick
            }
            .map {
                TransposeFact(
                    diatonic: $0.diatonic,
                    chromatic: $0.chromatic,
                    octaveChange: $0.octaveChange,
                    isDouble: $0.isDouble
                )
            }
    }

    private static func octaveShiftFacts(for note: MusicXMLNoteEvent, in score: MusicXMLScore) -> [OctaveShiftFact] {
        let applicable = score.octaveShiftEvents
            .filter { $0.tick <= note.tick && scope($0.scope, matches: note) }
            .sorted { lhs, rhs in
                lhs.tick == rhs.tick
                    ? scopeSpecificity(lhs.scope) < scopeSpecificity(rhs.scope)
                    : lhs.tick < rhs.tick
            }
        let latestByNumber = applicable.reduce(into: [String: MusicXMLOctaveShiftEvent]()) { result, event in
            result[event.numberToken ?? "1"] = event
        }
        return latestByNumber.values
            .filter { $0.kind != .stop }
            .sorted { ($0.numberToken ?? "1") < ($1.numberToken ?? "1") }
            .map { OctaveShiftFact(kind: $0.kind, size: $0.size, numberToken: $0.numberToken) }
    }

    private static func scope(_ scope: MusicXMLEventScope, matches note: MusicXMLNoteEvent) -> Bool {
        scope.partID == note.partID &&
            (scope.staff == nil || scope.staff == note.staff) &&
            (scope.voice == nil || scope.voice == note.voice)
    }

    private static func scopeSpecificity(_ scope: MusicXMLEventScope) -> Int {
        (scope.staff == nil ? 0 : 1) + (scope.voice == nil ? 0 : 1)
    }

    private init(
        sourceNotes: [SourceNote],
        performedOccurrences: [PerformedOccurrence]
    ) {
        self.sourceNotes = sourceNotes
        self.performedOccurrences = performedOccurrences
    }
}
