import Foundation

struct ScoreNotationProjection: Equatable, Sendable {
    struct BeamGroupID: Equatable, Hashable, Sendable, CustomStringConvertible {
        let partID: String
        let voice: Int
        let numberToken: String
        let startSourceNoteID: MusicXMLSourceNoteID

        var description: String {
            "\(partID):voice-\(voice):beam-\(numberToken):\(startSourceNoteID.description)"
        }
    }

    struct BeamFact: Equatable, Sendable {
        let groupID: BeamGroupID
        let sourceOrdinal: Int
        let numberToken: String?
        let value: MusicXMLBeamValue
        let repeaterToken: String?
        let fanToken: String?
    }

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

    struct KeySignatureFact: Equatable, Sendable {
        let fifths: Int
        let modeToken: String?
    }

    struct ClefFact: Equatable, Sendable {
        let signToken: String?
        let line: Int?
        let octaveChange: Int?
        let numberToken: String?
    }

    struct SourceNote: Equatable, Sendable {
        let id: MusicXMLSourceNoteID
        let chordID: MusicXMLSourceNoteID
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
        let stem: MusicXMLStem
        let beams: [BeamFact]
        let articulations: Set<MusicXMLArticulation>
        let arpeggiate: MusicXMLArpeggiate?
        let fingeringText: String?
        let keySignature: KeySignatureFact?
        let meter: MusicXMLMeter?
        let clef: ClefFact?
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
        let attributeTimeline = MusicXMLAttributeTimeline(
            timeSignatureEvents: sourceScore.timeSignatureEvents,
            keySignatureEvents: sourceScore.keySignatureEvents,
            clefEvents: sourceScore.clefEvents
        )
        let canonicalSources = Self.canonicalSources(from: sourceScore.notes)
        let beamFactsBySourceID = Self.beamFactsBySourceID(from: canonicalSources)
        sourceNotes = canonicalSources.map { canonical in
            let note = canonical.note
            let sourceID = canonical.sourceID
            return SourceNote(
                id: sourceID,
                chordID: canonical.chordID,
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
                stem: note.stem,
                beams: beamFactsBySourceID[sourceID] ?? [],
                articulations: note.articulations,
                arpeggiate: note.arpeggiate,
                fingeringText: note.fingeringText,
                keySignature: Self.keySignatureFact(for: note, in: attributeTimeline),
                meter: attributeTimeline.meter(
                    atTick: note.tick,
                    partID: note.partID,
                    staffNumber: note.staff ?? 1
                ),
                clef: Self.clefFact(for: note, in: attributeTimeline),
                transpose: Self.transposeFact(for: note, in: sourceScore),
                octaveShifts: Self.octaveShiftFacts(for: note, in: sourceScore)
            )
        }
        let sourceNotesByID = Dictionary(uniqueKeysWithValues: sourceNotes.map { ($0.id, $0) })
        let scoreNotesByPerformedID = Dictionary(uniqueKeysWithValues: sourceScore.notes.compactMap { note in
            note.performedID.map { ($0, note) }
        })
        var occurrencesByID: [MusicXMLPerformedNoteID: PerformedOccurrence] = [:]

        for event in plan.noteEvents {
            for performedNoteID in event.contributingPerformedNoteIDs {
                let sourceNoteID = performedNoteID.sourceID
                guard sourceNotesByID[sourceNoteID] != nil else {
                    continue
                }
                let writtenOnTick = scoreNotesByPerformedID[performedNoteID]?.tick ?? event.writtenOnTick
                if let existing = occurrencesByID[performedNoteID] {
                    let eventIDs = existing.performanceEventIDs.contains(event.id)
                        ? existing.performanceEventIDs
                        : existing.performanceEventIDs + [event.id]
                    occurrencesByID[performedNoteID] = PerformedOccurrence(
                        id: existing.id,
                        sourceNoteID: existing.sourceNoteID,
                        performanceEventIDs: eventIDs,
                        writtenOnTick: min(existing.writtenOnTick, writtenOnTick),
                        performedOnTick: min(existing.performedOnTick, event.performedOnTick),
                        performedOffTick: max(existing.performedOffTick, event.performedOffTick),
                        handAssignment: existing.handAssignment
                    )
                } else {
                    occurrencesByID[performedNoteID] = PerformedOccurrence(
                        id: performedNoteID,
                        sourceNoteID: sourceNoteID,
                        performanceEventIDs: [event.id],
                        writtenOnTick: writtenOnTick,
                        performedOnTick: event.performedOnTick,
                        performedOffTick: event.performedOffTick,
                        handAssignment: event.handAssignment
                    )
                }
            }
        }
        for note in sourceScore.notes {
            guard let sourceID = note.sourceID,
                  let performedID = note.performedID,
                  occurrencesByID[performedID] == nil
            else {
                continue
            }
            occurrencesByID[performedID] = PerformedOccurrence(
                id: performedID,
                sourceNoteID: sourceID,
                performanceEventIDs: [],
                writtenOnTick: note.tick,
                performedOnTick: note.tick,
                performedOffTick: note.tick + note.durationTicks,
                handAssignment: .unknown
            )
        }
        performedOccurrences = occurrencesByID.values.sorted { lhs, rhs in
            if lhs.writtenOnTick != rhs.writtenOnTick { return lhs.writtenOnTick < rhs.writtenOnTick }
            return lhs.id.description < rhs.id.description
        }
    }

    private struct CanonicalSource {
        let sourceID: MusicXMLSourceNoteID
        let chordID: MusicXMLSourceNoteID
        let note: MusicXMLNoteEvent
    }

    private struct BeamTrackKey: Hashable {
        let partID: String
        let voice: Int
        let numberToken: String
    }

    private static func canonicalSources(from notes: [MusicXMLNoteEvent]) -> [CanonicalSource] {
        var chordRootByPartID: [String: MusicXMLSourceNoteID] = [:]
        var seenSourceIDs: Set<MusicXMLSourceNoteID> = []
        var canonical: [CanonicalSource] = []

        for note in notes {
            guard let sourceID = note.sourceID else { continue }
            let chordID: MusicXMLSourceNoteID
            if note.isChord, let chordRoot = chordRootByPartID[note.partID] {
                chordID = chordRoot
            } else {
                chordID = sourceID
                chordRootByPartID[note.partID] = sourceID
            }
            guard seenSourceIDs.insert(sourceID).inserted else { continue }
            canonical.append(CanonicalSource(sourceID: sourceID, chordID: chordID, note: note))
        }
        return canonical
    }

    private static func beamFactsBySourceID(
        from sources: [CanonicalSource]
    ) -> [MusicXMLSourceNoteID: [BeamFact]] {
        var result: [MusicXMLSourceNoteID: [BeamFact]] = [:]
        var activeGroups: [BeamTrackKey: BeamGroupID] = [:]
        var startIndex = 0

        while startIndex < sources.count {
            let chordID = sources[startIndex].chordID
            var endIndex = startIndex + 1
            while endIndex < sources.count, sources[endIndex].chordID == chordID {
                endIndex += 1
            }
            let chordSources = sources[startIndex ..< endIndex]
            let factsByTrack = Dictionary(grouping: chordSources.flatMap { source in
                source.note.beams.enumerated().map { beamOrdinal, beam in
                    (source.sourceID, source.note, beamOrdinal, beam)
                }
            }) { entry in
                BeamTrackKey(
                    partID: entry.1.partID,
                    voice: entry.1.voice ?? 1,
                    numberToken: entry.3.numberToken ?? "1"
                )
            }

            for (track, entries) in factsByTrack {
                let values = entries.map(\.3.value)
                let isHook = values.contains(.forwardHook) || values.contains(.backwardHook)
                let groupID: BeamGroupID
                if values.contains(.begin) || isHook {
                    groupID = BeamGroupID(
                        partID: track.partID,
                        voice: track.voice,
                        numberToken: track.numberToken,
                        startSourceNoteID: chordID
                    )
                } else if let active = activeGroups[track] {
                    groupID = active
                } else {
                    // ponytail: malformed continue/end still keeps a traceable group rooted at itself.
                    groupID = BeamGroupID(
                        partID: track.partID,
                        voice: track.voice,
                        numberToken: track.numberToken,
                        startSourceNoteID: chordID
                    )
                }

                for (sourceID, _, sourceOrdinal, beam) in entries {
                    result[sourceID, default: []].append(BeamFact(
                        groupID: groupID,
                        sourceOrdinal: sourceOrdinal,
                        numberToken: beam.numberToken,
                        value: beam.value,
                        repeaterToken: beam.repeaterToken,
                        fanToken: beam.fanToken
                    ))
                }

                if values.contains(.end) || isHook {
                    activeGroups[track] = nil
                } else {
                    activeGroups[track] = groupID
                }
            }
            startIndex = endIndex
        }
        for sourceID in result.keys {
            result[sourceID]?.sort { $0.sourceOrdinal < $1.sourceOrdinal }
        }
        return result
    }

    private static func keySignatureFact(
        for note: MusicXMLNoteEvent,
        in timeline: MusicXMLAttributeTimeline
    ) -> KeySignatureFact? {
        timeline.keySignature(
            atTick: note.tick,
            partID: note.partID,
            staffNumber: note.staff ?? 1
        ).map { KeySignatureFact(fifths: $0.fifths, modeToken: $0.modeToken) }
    }

    private static func clefFact(
        for note: MusicXMLNoteEvent,
        in timeline: MusicXMLAttributeTimeline
    ) -> ClefFact? {
        timeline.clef(atTick: note.tick, partID: note.partID, staffNumber: note.staff ?? 1).map {
            ClefFact(
                signToken: $0.signToken,
                line: $0.line,
                octaveChange: $0.octaveChange,
                numberToken: $0.numberToken
            )
        }
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
