import Foundation

struct ScoreNotationProjection: Equatable, Sendable {
    struct Fallback: Equatable, Sendable {
        enum Kind: String, Equatable, Hashable, Sendable {
            case accidental
            case notehead
            case rest
            case beam
            case mark
        }

        enum Reason: String, Equatable, Hashable, Sendable {
            case microtonalAccidental
            case unsupportedAccidentalValue
            case unsupportedAccidentalToken
            case missingNoteType
            case unsupportedNoteType
            case unsupportedNoteheadToken
            case missingRestType
            case unsupportedRestType
            case unsupportedBeamValue
            case unsupportedArticulation
            case unsupportedArpeggioDirection
            case unsupportedPerformanceNotation
        }

        enum PlaceholderPolicy: String, Equatable, Sendable {
            case omit
            case reserveRhythmicSpace
        }

        let sourceID: MusicXMLSourceNoteID
        let sourceNotationID: MusicXMLPerformanceNotationSourceID?
        let kind: Kind
        let sourceKindToken: String?
        let reason: Reason
        let placeholderPolicy: PlaceholderPolicy

        init(
            sourceID: MusicXMLSourceNoteID,
            sourceNotationID: MusicXMLPerformanceNotationSourceID? = nil,
            kind: Kind,
            sourceKindToken: String? = nil,
            reason: Reason,
            placeholderPolicy: PlaceholderPolicy
        ) {
            self.sourceID = sourceID
            self.sourceNotationID = sourceNotationID
            self.kind = kind
            self.sourceKindToken = sourceKindToken
            self.reason = reason
            self.placeholderPolicy = placeholderPolicy
        }
    }

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

    struct Mark: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case dynamic
            case tempo
            case text
            case pedalStart
            case pedalStop
            case pedalChange
            case pedalContinue
            case fermata
            case repeatForward
            case repeatBackward
            case endingStart
            case endingStop
            case endingDiscontinue
        }

        let id: String
        let tick: Int
        let staff: Int?
        let voice: Int?
        let kind: Kind
        let text: String?
        let placementToken: String?
    }

    struct AttributeChange: Equatable, Sendable {
        let id: String
        let tick: Int
        let staff: Int
        let clef: ClefFact?
        let keySignatureFifths: Int?
        let previousKeySignatureFifths: Int?
        let meterText: String?
    }

    struct SourceNote: Equatable, Sendable {
        let id: MusicXMLSourceNoteID
        let chordID: MusicXMLSourceNoteID
        let writtenOnTick: Int
        let writtenDurationTicks: Int
        let writtenPitch: MusicXMLWrittenPitch?
        let writtenRhythm: MusicXMLWrittenRhythm?
        let noteheadToken: String?
        let isRest: Bool
        let isMeasureRest: Bool
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
        let performanceNotations: [MusicXMLPerformanceNotation]
        let fingerings: [MusicXMLFingering]
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
        let handAssignment: ScoreHandAssignment
    }

    struct Overlay: Equatable, Sendable {
        let activeEventIDs: Set<ScorePerformanceNoteEventID>
        let activeTickRange: Range<Int>?

        static let empty = Overlay(activeEventIDs: [], activeTickRange: nil)
    }

    let sourceNotes: [SourceNote]
    let performedOccurrences: [PerformedOccurrence]
    let marks: [Mark]
    let attributeChanges: [AttributeChange]
    let fallbacks: [Fallback]

    static let empty = ScoreNotationProjection(
        sourceNotes: [],
        performedOccurrences: [],
        marks: [],
        attributeChanges: [],
        fallbacks: []
    )

    init(
        plan: ScorePerformancePlan,
        sourceScore: MusicXMLScore,
        performedScore: MusicXMLScore? = nil
    ) {
        let performedScore = performedScore ?? sourceScore
        let sourceAttributeTimeline = MusicXMLAttributeTimeline(
            timeSignatureEvents: sourceScore.timeSignatureEvents,
            keySignatureEvents: sourceScore.keySignatureEvents,
            clefEvents: sourceScore.clefEvents
        )
        let performedAttributeTimeline = MusicXMLAttributeTimeline(
            timeSignatureEvents: performedScore.timeSignatureEvents,
            keySignatureEvents: performedScore.keySignatureEvents,
            clefEvents: performedScore.clefEvents
        )
        let grandStaffRoles = Dictionary(
            sourceScore.logicalInstruments
                .flatMap(\.grandStaffPartAssignments)
                .map { ($0.partID, $0.role) },
            uniquingKeysWith: { first, _ in first }
        )
        let canonicalSources = Self.canonicalSources(from: sourceScore.notes)
        let beamFactsBySourceID = Self.beamFactsBySourceID(from: canonicalSources)
        fallbacks = Self.fallbacks(from: canonicalSources)
        marks = Self.marks(
            from: performedScore,
            structuralSourceScore: sourceScore,
            performedMeasures: performedScore.measures,
            grandStaffRoles: grandStaffRoles
        )
        attributeChanges = Self.attributeChanges(
            from: performedScore,
            timeline: performedAttributeTimeline,
            after: canonicalSources.map(\.note.tick).min() ?? 0,
            grandStaffRoles: grandStaffRoles
        )
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
                noteheadToken: note.noteheadToken,
                isRest: note.isRest,
                isMeasureRest: note.isMeasureRest,
                isPrintObjectVisible: note.isPrintObjectVisible,
                staff: Self.displayStaff(
                    sourceStaff: note.staff ?? 1,
                    partID: note.partID,
                    grandStaffRoles: grandStaffRoles
                ),
                voice: note.voice ?? 1,
                isGrace: note.isGrace,
                ties: note.ties,
                slurs: note.slurs,
                tuplets: note.tuplets,
                stem: note.stem,
                beams: beamFactsBySourceID[sourceID] ?? [],
                articulations: note.articulations,
                arpeggiate: note.arpeggiate,
                performanceNotations: note.performanceNotations,
                fingerings: note.fingerings,
                keySignature: Self.keySignatureFact(for: note, in: sourceAttributeTimeline),
                meter: sourceAttributeTimeline.meter(
                    atTick: note.tick,
                    partID: note.partID,
                    staffNumber: note.staff ?? 1
                ),
                clef: Self.clefFact(for: note, in: sourceAttributeTimeline),
                transpose: Self.transposeFact(for: note, in: sourceScore),
                octaveShifts: Self.octaveShiftFacts(for: note, in: sourceScore)
            )
        }
        let sourceNotesByID = Dictionary(uniqueKeysWithValues: sourceNotes.map { ($0.id, $0) })
        let scoreNotesByPerformedID = Dictionary(uniqueKeysWithValues: performedScore.notes.compactMap { note in
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
                        handAssignment: existing.handAssignment
                    )
                } else {
                    occurrencesByID[performedNoteID] = PerformedOccurrence(
                        id: performedNoteID,
                        sourceNoteID: sourceNoteID,
                        performanceEventIDs: [event.id],
                        writtenOnTick: writtenOnTick,
                        handAssignment: event.handAssignment
                    )
                }
            }
        }
        for note in performedScore.notes {
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
                handAssignment: .unknown
            )
        }
        performedOccurrences = occurrencesByID.values.sorted { lhs, rhs in
            if lhs.writtenOnTick != rhs.writtenOnTick { return lhs.writtenOnTick < rhs.writtenOnTick }
            return lhs.id.description < rhs.id.description
        }
    }

    private init(
        sourceNotes: [SourceNote],
        performedOccurrences: [PerformedOccurrence],
        marks: [Mark],
        attributeChanges: [AttributeChange],
        fallbacks: [Fallback]
    ) {
        self.sourceNotes = sourceNotes
        self.performedOccurrences = performedOccurrences
        self.marks = marks
        self.attributeChanges = attributeChanges
        self.fallbacks = fallbacks
    }

    private static func marks(
        from score: MusicXMLScore,
        structuralSourceScore: MusicXMLScore,
        performedMeasures: [MusicXMLMeasureSpan],
        grandStaffRoles: [String: MusicXMLGrandStaffPartRole]
    ) -> [Mark] {
        var marks: [Mark] = []
        func projectedStaff(_ scope: MusicXMLEventScope) -> Int? {
            displayStaff(
                sourceStaff: scope.staff,
                partID: scope.partID,
                grandStaffRoles: grandStaffRoles
            )
        }
        marks.append(contentsOf: score.dynamicEvents.enumerated().compactMap { index, event in
            guard event.source == .directionDynamics else { return nil }
            return Mark(
                id: event.performedID?.description ?? "dynamic-\(event.tick)-\(index)",
                tick: event.tick,
                staff: projectedStaff(event.scope),
                voice: event.scope.voice,
                kind: .dynamic,
                text: event.markToken ?? dynamicText(velocity: event.velocity),
                placementToken: event.placementToken
            )
        })
        marks.append(contentsOf: score.tempoEvents.enumerated().compactMap { index, event in
            guard let text = tempoNotationText(event) else { return nil }
            return Mark(
                id: event.performedID?.description ?? "tempo-\(event.tick)-\(index)",
                tick: event.tick,
                staff: projectedStaff(event.scope),
                voice: event.scope.voice,
                kind: .tempo,
                text: text,
                placementToken: event.placementToken
            )
        })
        marks.append(contentsOf: score.wordsEvents.enumerated().map { index, event in
            Mark(
                id: event.performedID?.description ?? "words-\(event.tick)-\(index)",
                tick: event.tick,
                staff: projectedStaff(event.scope),
                voice: event.scope.voice,
                kind: .text,
                text: event.text,
                placementToken: event.placementToken
            )
        })
        var seenPedalMarkIDs: Set<String> = []
        for event in score.pedalEvents where event.controller == .damper {
            let kind: Mark.Kind = switch event.kind {
            case .start: .pedalStart
            case .stop: .pedalStop
            case .change: .pedalChange
            case .continue: .pedalContinue
            }
            let kindToken = switch kind {
            case .pedalStart: "start"
            case .pedalStop: "stop"
            case .pedalChange: "change"
            case .pedalContinue: "continue"
            default: "unknown"
            }
            let id = event.performedID?.description
                ?? "pedal-\(event.tick)-\(event.staff ?? 0)-\(kindToken)"
            // ponytail: playback expands pedal change to off/on; notation owns one mark per source direction.
            guard seenPedalMarkIDs.insert(id).inserted else { continue }
            marks.append(Mark(
                id: id,
                tick: event.tick,
                staff: displayStaff(
                    sourceStaff: event.staff,
                    partID: event.partID,
                    grandStaffRoles: grandStaffRoles
                ),
                voice: nil,
                kind: kind,
                text: nil,
                placementToken: event.placementToken
            ))
        }
        marks.append(contentsOf: score.fermataEvents.enumerated().map { index, event in
            Mark(
                id: event.performedID?.description ?? "fermata-\(event.tick)-\(index)",
                tick: event.tick,
                staff: projectedStaff(event.scope),
                voice: event.scope.voice,
                kind: .fermata,
                text: nil,
                placementToken: event.placementToken
            )
        })
        for (index, directive) in structuralSourceScore.repeatDirectives.enumerated() {
            guard let sourceMeasure = structuralSourceScore.measures.first(where: {
                $0.partID == directive.partID && $0.measureNumber == directive.measureNumber
            }) else { continue }
            let measures = performedMeasures.filter {
                $0.partID == directive.partID &&
                    $0.sourceMeasureIndex == sourceMeasure.sourceMeasureIndex &&
                    $0.sourceMeasureNumberToken == sourceMeasure.sourceMeasureNumberToken
            }
            for measure in measures.isEmpty ? [sourceMeasure] : measures {
                marks.append(Mark(
                    id: "repeat-\(directive.partID)-\(directive.measureNumber)-\(measure.occurrenceIndex)-\(index)",
                    tick: directive.direction == .forward ? measure.startTick : measure.endTick,
                    staff: nil,
                    voice: nil,
                    kind: directive.direction == .forward ? .repeatForward : .repeatBackward,
                    text: directive.times.map { "×\($0)" },
                    placementToken: nil
                ))
            }
        }
        for (index, directive) in structuralSourceScore.endingDirectives.enumerated() {
            guard let sourceMeasure = structuralSourceScore.measures.first(where: {
                $0.partID == directive.partID && $0.measureNumber == directive.measureNumber
            }) else { continue }
            let kind: Mark.Kind = switch directive.type {
            case .start: .endingStart
            case .stop: .endingStop
            case .discontinue: .endingDiscontinue
            }
            let measures = performedMeasures.filter {
                $0.partID == directive.partID &&
                    $0.sourceMeasureIndex == sourceMeasure.sourceMeasureIndex &&
                    $0.sourceMeasureNumberToken == sourceMeasure.sourceMeasureNumberToken
            }
            for measure in measures.isEmpty ? [sourceMeasure] : measures {
                marks.append(Mark(
                    id: "ending-\(directive.partID)-\(directive.measureNumber)-\(measure.occurrenceIndex)-\(index)",
                    tick: directive.type == .start ? measure.startTick : measure.endTick,
                    staff: 1,
                    voice: nil,
                    kind: kind,
                    text: directive.number,
                    placementToken: "above"
                ))
            }
        }
        return marks.sorted {
            $0.tick == $1.tick ? $0.id < $1.id : $0.tick < $1.tick
        }
    }

    private static func attributeChanges(
        from score: MusicXMLScore,
        timeline: MusicXMLAttributeTimeline,
        after initialTick: Int,
        grandStaffRoles: [String: MusicXMLGrandStaffPartRole]
    ) -> [AttributeChange] {
        struct Key: Hashable {
            let tick: Int
            let partID: String
            let sourceStaff: Int
            let displayStaff: Int
        }
        struct ChangedKinds: OptionSet {
            let rawValue: Int

            static let clef = ChangedKinds(rawValue: 1 << 0)
            static let key = ChangedKinds(rawValue: 1 << 1)
            static let meter = ChangedKinds(rawValue: 1 << 2)
        }

        var changesByKey: [Key: ChangedKinds] = [:]
        func record(tick: Int, partID: String, staff: Int?, kind: ChangedKinds) {
            guard tick > initialTick else { return }
            let sourceStaves = staff.map { [$0] }
                ?? (grandStaffRoles[partID] == nil ? [1, 2] : [1])
            for sourceStaff in sourceStaves {
                let displayStaff = displayStaff(
                    sourceStaff: sourceStaff,
                    partID: partID,
                    grandStaffRoles: grandStaffRoles
                )
                changesByKey[Key(
                    tick: tick,
                    partID: partID,
                    sourceStaff: sourceStaff,
                    displayStaff: displayStaff
                ), default: []].formUnion(kind)
            }
        }
        for event in score.clefEvents {
            record(
                tick: event.tick,
                partID: event.scope.partID,
                staff: event.scope.staff ?? event.numberToken.flatMap(Int.init),
                kind: .clef
            )
        }
        for event in score.keySignatureEvents {
            record(tick: event.tick, partID: event.scope.partID, staff: event.scope.staff, kind: .key)
        }
        for event in score.timeSignatureEvents {
            record(tick: event.tick, partID: event.scope.partID, staff: event.scope.staff, kind: .meter)
        }

        return changesByKey.map { key, kinds in
            let clefEvent = kinds.contains(.clef)
                ? timeline.clef(atTick: key.tick, partID: key.partID, staffNumber: key.sourceStaff)
                : nil
            let keyEvent = kinds.contains(.key)
                ? timeline.keySignature(atTick: key.tick, partID: key.partID, staffNumber: key.sourceStaff)
                : nil
            let previousKeyEvent = kinds.contains(.key)
                ? timeline.keySignature(atTick: key.tick - 1, partID: key.partID, staffNumber: key.sourceStaff)
                : nil
            return AttributeChange(
                id: "attribute-\(key.partID)-\(key.tick)-staff-\(key.displayStaff)",
                tick: key.tick,
                staff: key.displayStaff,
                clef: clefEvent.map {
                    ClefFact(
                        signToken: $0.signToken,
                        line: $0.line,
                        octaveChange: $0.octaveChange,
                        numberToken: $0.numberToken
                    )
                },
                keySignatureFifths: keyEvent?.fifths,
                previousKeySignatureFifths: previousKeyEvent?.fifths,
                meterText: kinds.contains(.meter)
                    ? timeline.meter(
                        atTick: key.tick,
                        partID: key.partID,
                        staffNumber: key.sourceStaff
                    )?.displayText
                    : nil
            )
        }.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.staff < $1.staff
        }
    }

    private static func displayStaff(
        sourceStaff: Int,
        partID: String,
        grandStaffRoles: [String: MusicXMLGrandStaffPartRole]
    ) -> Int {
        grandStaffRoles[partID]?.displayStaff ?? sourceStaff
    }

    private static func displayStaff(
        sourceStaff: Int?,
        partID: String,
        grandStaffRoles: [String: MusicXMLGrandStaffPartRole]
    ) -> Int? {
        grandStaffRoles[partID]?.displayStaff ?? sourceStaff
    }

    private static func dynamicText(velocity: UInt8) -> String {
        switch velocity {
        case ...34: "ppp"
        case ...44: "pp"
        case ...54: "p"
        case ...67: "mp"
        case ...82: "mf"
        case ...97: "f"
        case ...110: "ff"
        default: "fff"
        }
    }

    private static func tempoNotationText(_ event: MusicXMLTempoEvent) -> String? {
        guard let beatUnitToken = event.notationBeatUnitToken,
              let perMinute = event.notationPerMinute
        else {
            return nil
        }
        let beatUnit = switch beatUnitToken {
        case "whole": "𝅝"
        case "half": "𝅗𝅥"
        case "quarter": "♩"
        case "eighth": "♪"
        default: beatUnitToken
        }
        let dots = String(repeating: ".", count: event.notationBeatUnitDotCount)
        let tempo = perMinute.formatted(.number.precision(.fractionLength(0 ... 2)))
        return "\(beatUnit)\(dots) = \(tempo)"
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

    private static func fallbacks(from sources: [CanonicalSource]) -> [Fallback] {
        let supportedAccidentals = Set([
            "sharp", "flat", "natural", "double-sharp", "sharp-sharp", "flat-flat", "double-flat",
        ])
        var result: [Fallback] = []

        for source in sources {
            let note = source.note
            let rhythmToken = note.writtenRhythm?.typeToken?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if note.isMeasureRest {
                // MusicXML whole-measure rests are valid without a <type> child.
            } else if rhythmToken == nil || rhythmToken?.isEmpty == true {
                result.append(Fallback(
                    sourceID: source.sourceID,
                    kind: note.isRest ? .rest : .notehead,
                    reason: note.isRest ? .missingRestType : .missingNoteType,
                    placeholderPolicy: .reserveRhythmicSpace
                ))
            } else if GrandStaffNoteValue(sourceTypeToken: rhythmToken).isSupported == false {
                result.append(Fallback(
                    sourceID: source.sourceID,
                    kind: note.isRest ? .rest : .notehead,
                    reason: note.isRest ? .unsupportedRestType : .unsupportedNoteType,
                    placeholderPolicy: .reserveRhythmicSpace
                ))
            }

            if let noteheadToken = normalizedToken(note.noteheadToken), noteheadToken != "normal" {
                result.append(Fallback(
                    sourceID: source.sourceID,
                    kind: .notehead,
                    sourceKindToken: noteheadToken,
                    reason: .unsupportedNoteheadToken,
                    placeholderPolicy: .reserveRhythmicSpace
                ))
            }

            if let pitch = note.writtenPitch {
                let accidentalToken = pitch.accidentalToken?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if pitch.alter.isFinite == false || (-2.0 ... 2.0).contains(pitch.alter) == false {
                    result.append(Fallback(
                        sourceID: source.sourceID,
                        kind: .accidental,
                        reason: .unsupportedAccidentalValue,
                        placeholderPolicy: .omit
                    ))
                } else if pitch.alter.rounded() != pitch.alter {
                    result.append(Fallback(
                        sourceID: source.sourceID,
                        kind: .accidental,
                        reason: .microtonalAccidental,
                        placeholderPolicy: .omit
                    ))
                } else if let accidentalToken, supportedAccidentals.contains(accidentalToken) == false {
                    result.append(Fallback(
                        sourceID: source.sourceID,
                        kind: .accidental,
                        reason: .unsupportedAccidentalToken,
                        placeholderPolicy: .omit
                    ))
                }
            }

            if note.beams.contains(where: {
                if case .unsupported = $0.value { return true }
                return false
            }) {
                result.append(Fallback(
                    sourceID: source.sourceID,
                    kind: .beam,
                    reason: .unsupportedBeamValue,
                    placeholderPolicy: .omit
                ))
            }
            if note.articulations.contains(.detachedLegato) {
                result.append(Fallback(
                    sourceID: source.sourceID,
                    kind: .mark,
                    reason: .unsupportedArticulation,
                    placeholderPolicy: .omit
                ))
            }
            if let arpeggiate = note.arpeggiate,
               arpeggiate.directionToken != nil,
               arpeggiate.direction == nil
            {
                result.append(Fallback(
                    sourceID: source.sourceID,
                    kind: .mark,
                    reason: .unsupportedArpeggioDirection,
                    placeholderPolicy: .omit
                ))
            }
            result.append(contentsOf: note.performanceNotations.map { notation in
                Fallback(
                    sourceID: source.sourceID,
                    sourceNotationID: notation.sourceID,
                    kind: .mark,
                    sourceKindToken: notation.diagnosticKindToken,
                    reason: .unsupportedPerformanceNotation,
                    placeholderPolicy: .omit
                )
            })
        }
        return result
    }

    private static func normalizedToken(_ token: String?) -> String? {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.isEmpty ? nil : normalized
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

}
