import Foundation

struct ScorePerformancePlanBuilder {
    func build(
        sourceIdentity: ScorePerformanceSourceIdentity,
        order: MusicXMLOrderSelection,
        logicalInstrument: MusicXMLLogicalInstrument,
        notes: [MusicXMLNoteEvent],
        timingSchedule: ScoreTimingSchedule,
        velocityResolver: MusicXMLVelocityResolver,
        expressivity: MusicXMLExpressivityOptions,
        handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment],
        tempoMap: MusicXMLTempoMap? = nil,
        pedalTimeline: MusicXMLPedalTimeline? = nil,
        tempoAnnotations: [MusicXMLTempoWordAnnotation] = [],
        fermataTimeline: MusicXMLFermataTimeline? = nil,
        interpretationProfileID: String = MusicXMLInterpretationProfile.generic.id
    ) -> ScorePerformancePlan {
        let memberPartIDs = Set(logicalInstrument.memberPartIDs)
        let timingByNoteIndex = timingSchedule.entries.reduce(into: [Int: ScoreTimingEntry]()) { entries, entry in
            entries[entry.noteIndex] = entry
        }
        let replacedNoteIndices = timingSchedule.notationResolutions.reduce(into: Set<Int>()) { indices, resolution in
            guard case .generated = resolution.status else { return }
            indices.formUnion(resolution.replacesSourceNoteIndices)
        }
        var approximations = planApproximations(
            sourceIdentity: sourceIdentity,
            order: order,
            logicalInstrument: logicalInstrument,
            timingSchedule: timingSchedule
        )
        var events: [ScorePerformanceNoteEvent] = []
        var activeTieEventIndexByKey: [TieKey: Int] = [:]

        for noteIndex in notes.indices.sorted(by: { noteOrder($0, $1, notes: notes, timing: timingByNoteIndex) }) {
            let note = notes[noteIndex]
            guard memberPartIDs.contains(note.partID), note.isRest == false else { continue }
            guard note.isGrace == false || expressivity.graceEnabled else { continue }
            guard replacedNoteIndices.contains(noteIndex) == false else { continue }
            guard let midiNote = note.midiNote else {
                approximations.append(unsupportedNote(note, reason: "pitched-note-missing-midi"))
                continue
            }
            guard let sourceNoteID = note.sourceID, let performedNoteID = note.performedID else {
                approximations.append(unsupportedNote(note, reason: "pitched-note-missing-source-identity"))
                continue
            }
            guard let timing = timingByNoteIndex[noteIndex] else {
                approximations.append(unsupportedNote(note, reason: "pitched-note-missing-timing-entry"))
                continue
            }

            let event = makeSourceEvent(
                note: note,
                sourceNoteID: sourceNoteID,
                performedNoteID: performedNoteID,
                midiNote: midiNote,
                timing: timing,
                velocityResolver: velocityResolver,
                handAssignments: handAssignments
            )
            let tieKey = TieKey(
                partID: note.partID,
                midiNote: midiNote,
                staff: event.staff,
                voice: event.voice,
                occurrenceIndex: note.performedOccurrenceIndex
            )

            switch tieCategory(for: note) {
            case .start:
                events.append(event)
                activeTieEventIndexByKey[tieKey] = events.count - 1
            case .middle:
                if let eventIndex = activeTieEventIndexByKey[tieKey] {
                    events[eventIndex] = mergingTie(events[eventIndex], with: event)
                } else {
                    events.append(event)
                    activeTieEventIndexByKey[tieKey] = events.count - 1
                }
            case .end:
                if let eventIndex = activeTieEventIndexByKey.removeValue(forKey: tieKey) {
                    events[eventIndex] = mergingTie(events[eventIndex], with: event)
                } else {
                    events.append(event)
                }
            case .normal:
                events.append(event)
            }
        }

        events.append(contentsOf: generatedEvents(
            from: timingSchedule.generatedNotes,
            notes: notes,
            memberPartIDs: memberPartIDs,
            timingByNoteIndex: timingByNoteIndex,
            velocityResolver: velocityResolver,
            handAssignments: handAssignments,
            approximations: &approximations
        ))
        events.sort(by: eventOrder)
        approximations.append(contentsOf: events.flatMap { event in
            event.timingProvenance.compactMap { provenance in
                guard provenance.kind == .approximation, let reason = provenance.detail else { return nil }
                return ScorePerformanceApproximation(
                    scope: .note,
                    eventIdentity: event.id.description,
                    reason: reason
                )
            }
        })
        approximations.append(contentsOf: velocityResolver.wedgeApproximations.map { approximation in
            ScorePerformanceApproximation(
                scope: .note,
                eventIdentity: approximation.sourceID?.description,
                reason: approximation.reason
            )
        })
        approximations.append(contentsOf: tempoAnnotations.compactMap { annotation in
            guard case let .approximation(reason) = annotation.resolution else { return nil }
            return ScorePerformanceApproximation(
                scope: .annotation,
                eventIdentity: annotation.sourceID?.description,
                reason: reason
            )
        })

        let annotations = performanceAnnotations(
            notes: notes,
            noteEvents: events,
            timingSchedule: timingSchedule,
            tempoAnnotations: tempoAnnotations,
            fermataTimeline: fermataTimeline
        )

        return ScorePerformancePlan(
            id: ScorePerformancePlanID(rawValue: [
                sourceIdentity.songID.uuidString.lowercased(),
                sourceIdentity.scoreRevision,
                sourceIdentity.logicalInstrumentID,
                order.applied.rawValue,
                interpretationProfileID,
            ].joined(separator: "|")),
            sourceScoreIdentity: sourceIdentity,
            order: order,
            resolution: ScorePerformanceTickResolution(ticksPerQuarter: MusicXMLTempoMap.ticksPerQuarter),
            noteEvents: events,
            tempoEvents: tempoMap?.performanceEvents().map(tempoEvent) ?? [],
            controllerEvents: pedalTimeline?.controllerChanges().map(controllerEvent) ?? [],
            annotations: annotations,
            approximations: approximations
        )
    }
}

private extension ScorePerformancePlanBuilder {
    struct TieKey: Hashable {
        let partID: String
        let midiNote: Int
        let staff: Int
        let voice: Int
        let occurrenceIndex: Int
    }

    enum TieCategory {
        case start
        case middle
        case end
        case normal
    }

    func makeSourceEvent(
        note: MusicXMLNoteEvent,
        sourceNoteID: MusicXMLSourceNoteID,
        performedNoteID: MusicXMLPerformedNoteID,
        midiNote: Int,
        timing: ScoreTimingEntry,
        velocityResolver: MusicXMLVelocityResolver,
        handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment]
    ) -> ScorePerformanceNoteEvent {
        ScorePerformanceNoteEvent(
            id: ScorePerformanceNoteEventID(performedNoteID: performedNoteID, generatedOrdinal: nil),
            sourceNoteID: sourceNoteID,
            performedNoteID: performedNoteID,
            contributingSourceNoteIDs: [sourceNoteID],
            contributingPerformedNoteIDs: [performedNoteID],
            purpose: .source,
            writtenOnTick: timing.writtenOnTick,
            writtenOffTick: timing.writtenOffTick,
            performedOnTick: timing.performedOnTick,
            performedOffTick: timing.performedOffTick,
            writtenPitch: note.writtenPitch.map(writtenPitch),
            midiNote: midiNote,
            velocityResolution: velocityResolution(velocityResolver.resolution(for: note)),
            staff: note.staff ?? 1,
            voice: note.voice ?? 1,
            handAssignment: handAssignments[sourceNoteID] ?? .unknown,
            fingeringText: note.fingeringText,
            timingProvenance: timing.provenance.map(provenance)
        )
    }

    func generatedEvents(
        from generatedNotes: [ScoreGeneratedNoteEvent],
        notes: [MusicXMLNoteEvent],
        memberPartIDs: Set<String>,
        timingByNoteIndex: [Int: ScoreTimingEntry],
        velocityResolver: MusicXMLVelocityResolver,
        handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment],
        approximations: inout [ScorePerformanceApproximation]
    ) -> [ScorePerformanceNoteEvent] {
        let ordered = generatedNotes.sorted { lhs, rhs in
            if lhs.onTick != rhs.onTick { return lhs.onTick < rhs.onTick }
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            let lhsSource = lhs.sourceNoteIndices.first ?? Int.max
            let rhsSource = rhs.sourceNoteIndices.first ?? Int.max
            if lhsSource != rhsSource { return lhsSource < rhsSource }
            return lhs.ordinal < rhs.ordinal
        }
        var nextOrdinalByPerformedNoteID: [MusicXMLPerformedNoteID: Int] = [:]
        var output: [ScorePerformanceNoteEvent] = []

        for generated in ordered {
            let validIndices = generated.sourceNoteIndices.filter {
                notes.indices.contains($0) && memberPartIDs.contains(notes[$0].partID)
            }
            guard let primaryIndex = validIndices.first,
                  let primarySourceID = notes[primaryIndex].sourceID,
                  let primaryPerformedID = notes[primaryIndex].performedID
            else {
                approximations.append(ScorePerformanceApproximation(
                    scope: .note,
                    eventIdentity: generated.sourceNotationID?.description,
                    reason: "generated-note-missing-source-identity"
                ))
                continue
            }
            let sourceNoteIDs = validIndices.compactMap { notes[$0].sourceID }
            let performedNoteIDs = validIndices.compactMap { notes[$0].performedID }
            let timings = validIndices.compactMap { timingByNoteIndex[$0] }
            let generatedOrdinal = nextOrdinalByPerformedNoteID[primaryPerformedID, default: 0]
            nextOrdinalByPerformedNoteID[primaryPerformedID] = generatedOrdinal + 1
            let primaryNote = notes[primaryIndex]

            output.append(ScorePerformanceNoteEvent(
                id: ScorePerformanceNoteEventID(
                    performedNoteID: primaryPerformedID,
                    generatedOrdinal: generatedOrdinal
                ),
                sourceNoteID: primarySourceID,
                performedNoteID: primaryPerformedID,
                contributingSourceNoteIDs: sourceNoteIDs,
                contributingPerformedNoteIDs: performedNoteIDs,
                purpose: purpose(generated.purpose),
                writtenOnTick: timings.map(\.writtenOnTick).min() ?? primaryNote.tick,
                writtenOffTick: timings.map(\.writtenOffTick).max()
                    ?? (primaryNote.tick + max(0, primaryNote.durationTicks)),
                performedOnTick: generated.onTick,
                performedOffTick: max(generated.onTick, generated.offTick),
                writtenPitch: primaryNote.writtenPitch.map(writtenPitch),
                midiNote: generated.midiNote,
                velocityResolution: velocityResolution(velocityResolver.resolution(for: primaryNote)),
                staff: primaryNote.staff ?? 1,
                voice: primaryNote.voice ?? 1,
                handAssignment: handAssignments[primarySourceID] ?? .unknown,
                fingeringText: primaryNote.fingeringText,
                timingProvenance: [ScorePerformanceProvenance(
                    kind: .performanceNotation,
                    sourceIdentity: generated.sourceNotationID?.description,
                    detail: "\(generated.notationKind.rawValue):\(generated.interpretationProfileID)"
                )]
            ))
        }
        return output
    }

    func planApproximations(
        sourceIdentity: ScorePerformanceSourceIdentity,
        order: MusicXMLOrderSelection,
        logicalInstrument: MusicXMLLogicalInstrument,
        timingSchedule: ScoreTimingSchedule
    ) -> [ScorePerformanceApproximation] {
        var output: [ScorePerformanceApproximation] = []
        if sourceIdentity.logicalInstrumentID != logicalInstrument.id {
            output.append(ScorePerformanceApproximation(
                scope: .plan,
                eventIdentity: logicalInstrument.id,
                reason: "source-logical-instrument-mismatch"
            ))
        }
        if let reason = order.approximationReason {
            output.append(ScorePerformanceApproximation(
                scope: .plan,
                eventIdentity: nil,
                reason: reason
            ))
        }
        for resolution in timingSchedule.notationResolutions {
            guard case let .unsupported(reason) = resolution.status else { continue }
            output.append(ScorePerformanceApproximation(
                scope: .note,
                eventIdentity: resolution.sourceNotationID?.description,
                reason: reason
            ))
        }
        return output
    }

    func performanceAnnotations(
        notes: [MusicXMLNoteEvent],
        noteEvents: [ScorePerformanceNoteEvent],
        timingSchedule: ScoreTimingSchedule,
        tempoAnnotations: [MusicXMLTempoWordAnnotation],
        fermataTimeline: MusicXMLFermataTimeline?
    ) -> [ScorePerformanceAnnotation] {
        var output = timingSchedule.directives.map { directive in
            let matchingEvent = directive.sourceNotationID.flatMap { notationID in
                noteEvents.first {
                    $0.contributingSourceNoteIDs.contains(notationID.sourceNoteID)
                        && $0.performedOffTick == directive.tick
                }
            }
            return ScorePerformanceAnnotation(
                sourceDirectionID: nil,
                performedOccurrenceIndex: matchingEvent?.performedNoteID.occurrenceIndex ?? 0,
                tick: directive.tick,
                durationTicks: directive.durationTicks,
                kind: .pause,
                text: directive.kind.rawValue,
                provenance: [ScorePerformanceProvenance(
                    kind: .performanceNotation,
                    sourceIdentity: directive.sourceNotationID?.description,
                    detail: directive.interpretationProfileID
                )]
            )
        }
        output.append(contentsOf: tempoAnnotations.map { annotation in
            ScorePerformanceAnnotation(
                sourceDirectionID: annotation.sourceID,
                performedOccurrenceIndex: annotation.performedOccurrenceIndex,
                tick: annotation.tick,
                durationTicks: nil,
                kind: .tempoWord,
                text: annotation.text,
                provenance: [tempoAnnotationProvenance(annotation)]
            )
        })
        output.append(contentsOf: phraseAnnotations(notes: notes, noteEvents: noteEvents))
        output.append(contentsOf: fermataAnnotations(
            noteEvents: noteEvents,
            fermataTimeline: fermataTimeline
        ))
        return output.sorted(by: annotationOrder)
    }

    func phraseAnnotations(
        notes: [MusicXMLNoteEvent],
        noteEvents: [ScorePerformanceNoteEvent]
    ) -> [ScorePerformanceAnnotation] {
        notes.flatMap { note -> [ScorePerformanceAnnotation] in
            guard let performedID = note.performedID,
                  let event = noteEvents.first(where: { $0.contributingPerformedNoteIDs.contains(performedID) })
            else {
                return []
            }
            return note.performanceNotations.compactMap { notation in
                guard notation.kind == .breathMark else { return nil }
                return ScorePerformanceAnnotation(
                    sourceDirectionID: nil,
                    performedOccurrenceIndex: note.performedOccurrenceIndex,
                    tick: event.performedOffTick,
                    durationTicks: nil,
                    kind: .phrase,
                    text: notation.textToken,
                    provenance: [ScorePerformanceProvenance(
                        kind: .performanceNotation,
                        sourceIdentity: notation.sourceID?.description,
                        detail: notation.kind.rawValue
                    )]
                )
            }
        }
    }

    func fermataAnnotations(
        noteEvents: [ScorePerformanceNoteEvent],
        fermataTimeline: MusicXMLFermataTimeline?
    ) -> [ScorePerformanceAnnotation] {
        guard let fermataTimeline else { return [] }
        return fermataTimeline.holds.map { hold in
            let matchingPerformedIDs = Set(hold.contributingPerformedNoteIDs)
            let holdTick = noteEvents
                .filter { event in
                    event.contributingPerformedNoteIDs.contains { matchingPerformedIDs.contains($0) }
                }
                .map(\.performedOffTick)
                .max() ?? hold.tick
            return ScorePerformanceAnnotation(
                sourceDirectionID: hold.sourceDirectionID,
                performedOccurrenceIndex: hold.performedOccurrenceIndex,
                tick: holdTick,
                durationTicks: hold.extraTicks,
                kind: .pause,
                text: "fermata",
                provenance: hold.provenanceSourceIdentities.map { sourceIdentity in
                    ScorePerformanceProvenance(
                        kind: .interpretationProfile,
                        sourceIdentity: sourceIdentity,
                        detail: fermataTimeline.interpretationProfileID
                    )
                }
            )
        }
    }

    func mergingTie(
        _ event: ScorePerformanceNoteEvent,
        with continuation: ScorePerformanceNoteEvent
    ) -> ScorePerformanceNoteEvent {
        ScorePerformanceNoteEvent(
            id: event.id,
            sourceNoteID: event.sourceNoteID,
            performedNoteID: event.performedNoteID,
            contributingSourceNoteIDs: appendingUnique(
                event.contributingSourceNoteIDs,
                continuation.contributingSourceNoteIDs
            ),
            contributingPerformedNoteIDs: appendingUnique(
                event.contributingPerformedNoteIDs,
                continuation.contributingPerformedNoteIDs
            ),
            purpose: event.purpose,
            writtenOnTick: min(event.writtenOnTick, continuation.writtenOnTick),
            writtenOffTick: max(event.writtenOffTick, continuation.writtenOffTick),
            performedOnTick: min(event.performedOnTick, continuation.performedOnTick),
            performedOffTick: max(event.performedOffTick, continuation.performedOffTick),
            writtenPitch: event.writtenPitch,
            midiNote: event.midiNote,
            velocityResolution: event.velocityResolution,
            staff: event.staff,
            voice: event.voice,
            handAssignment: event.handAssignment,
            fingeringText: event.fingeringText,
            timingProvenance: appendingUnique(event.timingProvenance, continuation.timingProvenance)
        )
    }

    func tieCategory(for note: MusicXMLNoteEvent) -> TieCategory {
        if note.startsTie, note.stopsTie { return .middle }
        if note.startsTie { return .start }
        if note.stopsTie { return .end }
        return .normal
    }

    func noteOrder(
        _ lhsIndex: Int,
        _ rhsIndex: Int,
        notes: [MusicXMLNoteEvent],
        timing: [Int: ScoreTimingEntry]
    ) -> Bool {
        let lhsOnTick = timing[lhsIndex]?.performedOnTick ?? Int.max
        let rhsOnTick = timing[rhsIndex]?.performedOnTick ?? Int.max
        if lhsOnTick != rhsOnTick { return lhsOnTick < rhsOnTick }
        let lhs = notes[lhsIndex]
        let rhs = notes[rhsIndex]
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if (lhs.staff ?? 1) != (rhs.staff ?? 1) { return (lhs.staff ?? 1) < (rhs.staff ?? 1) }
        if (lhs.voice ?? 1) != (rhs.voice ?? 1) { return (lhs.voice ?? 1) < (rhs.voice ?? 1) }
        return (lhs.sourceID?.description ?? "") < (rhs.sourceID?.description ?? "")
    }

    func eventOrder(_ lhs: ScorePerformanceNoteEvent, _ rhs: ScorePerformanceNoteEvent) -> Bool {
        if lhs.performedOnTick != rhs.performedOnTick { return lhs.performedOnTick < rhs.performedOnTick }
        if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
        if lhs.staff != rhs.staff { return lhs.staff < rhs.staff }
        if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
        return lhs.id.description < rhs.id.description
    }

    func writtenPitch(_ pitch: MusicXMLWrittenPitch) -> ScorePerformanceWrittenPitch {
        ScorePerformanceWrittenPitch(
            step: pitch.step,
            octave: pitch.octave,
            alter: pitch.alter,
            accidentalToken: pitch.accidentalToken
        )
    }

    func velocityResolution(_ resolution: MusicXMLVelocityResolution) -> ScorePerformanceVelocityResolution {
        ScorePerformanceVelocityResolution(
            baseVelocity: resolution.baseVelocity,
            curveVelocity: resolution.curveVelocity,
            articulationDelta: resolution.articulationDelta,
            unclampedVelocity: resolution.unclampedVelocity,
            velocity: resolution.velocity
        )
    }

    func tempoEvent(_ event: MusicXMLTempoMap.PerformanceEvent) -> ScorePerformanceTempoEvent {
        ScorePerformanceTempoEvent(
            sourceDirectionID: event.sourceDirectionID,
            performedOccurrenceIndex: event.performedOccurrenceIndex,
            tick: event.tick,
            quarterBPM: event.quarterBPM,
            endTick: event.endTick,
            endQuarterBPM: event.endQuarterBPM
        )
    }

    func controllerEvent(_ event: MusicXMLPedalTimeline.ControllerChange) -> ScorePerformanceControllerEvent {
        ScorePerformanceControllerEvent(
            sourceDirectionID: event.sourceDirectionID,
            performedOccurrenceIndex: event.performedOccurrenceIndex,
            tick: event.tick,
            controllerNumber: event.controllerNumber,
            value: event.value,
            outputCapabilityRequirement: .continuousControlChange
        )
    }

    func tempoAnnotationProvenance(_ annotation: MusicXMLTempoWordAnnotation) -> ScorePerformanceProvenance {
        let detail: String
        let kind: ScorePerformanceProvenanceKind
        switch annotation.resolution {
        case .tempoRamp:
            kind = .score
            detail = "tempo-ramp"
        case .tempoEvent:
            kind = .score
            detail = "tempo-event"
        case .explicitEventAtMarker:
            kind = .score
            detail = "explicit-event-at-marker"
        case let .approximation(reason):
            kind = .approximation
            detail = reason
        }
        return ScorePerformanceProvenance(
            kind: kind,
            sourceIdentity: annotation.sourceID?.description,
            detail: detail
        )
    }

    func provenance(_ value: ScoreTimingProvenance) -> ScorePerformanceProvenance {
        switch value {
        case .score:
            ScorePerformanceProvenance(kind: .score, sourceIdentity: nil, detail: nil)
        case .performanceOffset:
            ScorePerformanceProvenance(kind: .performanceOffset, sourceIdentity: nil, detail: nil)
        case let .grace(kind):
            ScorePerformanceProvenance(kind: .grace, sourceIdentity: nil, detail: String(describing: kind))
        case let .arpeggio(numberToken, direction):
            ScorePerformanceProvenance(
                kind: .arpeggio,
                sourceIdentity: nil,
                detail: "number=\(numberToken),direction=\(direction.rawValue)"
            )
        case let .interpretationProfile(id):
            ScorePerformanceProvenance(kind: .interpretationProfile, sourceIdentity: nil, detail: id)
        case let .performanceNotation(kind, sourceID, profileID):
            ScorePerformanceProvenance(
                kind: .performanceNotation,
                sourceIdentity: sourceID?.description,
                detail: "\(kind.rawValue):\(profileID)"
            )
        case let .approximation(reason):
            ScorePerformanceProvenance(kind: .approximation, sourceIdentity: nil, detail: reason)
        }
    }

    func purpose(_ value: ScoreGeneratedNotePurpose) -> ScorePerformanceNotePurpose {
        switch value {
        case .ornament: .ornament
        case .tremolo: .tremolo
        case .glissando: .glissando
        }
    }

    func annotationOrder(_ lhs: ScorePerformanceAnnotation, _ rhs: ScorePerformanceAnnotation) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.performedOccurrenceIndex != rhs.performedOccurrenceIndex {
            return lhs.performedOccurrenceIndex < rhs.performedOccurrenceIndex
        }
        let lhsSource = lhs.sourceDirectionID?.description ?? lhs.provenance.first?.sourceIdentity ?? ""
        let rhsSource = rhs.sourceDirectionID?.description ?? rhs.provenance.first?.sourceIdentity ?? ""
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        return (lhs.text ?? "") < (rhs.text ?? "")
    }

    func unsupportedNote(_ note: MusicXMLNoteEvent, reason: String) -> ScorePerformanceApproximation {
        ScorePerformanceApproximation(
            scope: .note,
            eventIdentity: note.performedID?.description ?? note.sourceID?.description,
            reason: reason
        )
    }

    func appendingUnique<Value: Equatable>(_ lhs: [Value], _ rhs: [Value]) -> [Value] {
        rhs.reduce(into: lhs) { output, value in
            if output.contains(value) == false {
                output.append(value)
            }
        }
    }
}
