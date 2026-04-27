import Foundation

struct PianoHighlightGuideBuildInput {
    let score: MusicXMLScore
    let steps: [PracticeStep]
    let noteSpans: [MusicXMLNoteSpan]
    let expressivity: MusicXMLExpressivityOptions

    init(
        score: MusicXMLScore,
        steps: [PracticeStep],
        noteSpans: [MusicXMLNoteSpan],
        expressivity: MusicXMLExpressivityOptions = MusicXMLExpressivityOptions()
    ) {
        self.score = score
        self.steps = steps
        self.noteSpans = noteSpans
        self.expressivity = expressivity
    }
}

struct PianoHighlightGuideBuilderService {
    private struct SourceNoteKey: Hashable {
        let midiNote: Int
        let staff: Int
        let tick: Int
    }

    private struct SpanKey: Hashable {
        let midiNote: Int
        let staff: Int
        let onTick: Int
    }

    private struct ReleaseEvent {
        let tick: Int
        let note: PianoHighlightNote
    }

    private let playableRange = 21 ... 108

    func buildGuides(input: PianoHighlightGuideBuildInput) -> [PianoHighlightGuide] {
        guard input.steps.isEmpty == false else { return [] }

        let sourceNotesByKey = makeSourceNotesByKey(score: input.score, expressivity: input.expressivity)
        let spanByKey = makeSpanByKey(input.noteSpans)
        let practiceStepIndexByTick = Dictionary(uniqueKeysWithValues: input.steps.enumerated().map { index, step in
            (step.tick, index)
        })
        let restTicks = Set(input.score.notes.filter(\.isRest).map(\.tick))

        var occurrenceCounter = 0
        var triggersByTick: [Int: [PianoHighlightNote]] = [:]
        var releasesByTick: [Int: [PianoHighlightNote]] = [:]

        for step in input.steps {
            for stepNote in step.notes {
                let onTick = step.tick + stepNote.onTickOffset
                let staff = stepNote.staff ?? 1
                let source = sourceNotesByKey[SourceNoteKey(midiNote: stepNote.midiNote, staff: staff, tick: onTick)]
                    ?? sourceNotesByKey[SourceNoteKey(midiNote: stepNote.midiNote, staff: staff, tick: step.tick)]
                let voice = source?.voice ?? 1
                let span = spanByKey[SpanKey(midiNote: stepNote.midiNote, staff: staff, onTick: onTick)]
                    ?? spanByKey[SpanKey(midiNote: stepNote.midiNote, staff: staff, onTick: step.tick)]
                let offTick = max(onTick, span?.offTick ?? (onTick + max(1, source?.durationTicks ?? 1)))
                occurrenceCounter += 1
                let note = PianoHighlightNote(
                    occurrenceID: "h-\(occurrenceCounter)-\(stepNote.midiNote)-\(onTick)-\(staff)-\(voice)",
                    midiNote: stepNote.midiNote,
                    staff: stepNote.staff,
                    voice: voice,
                    velocity: stepNote.velocity,
                    onTick: onTick,
                    offTick: offTick,
                    fingeringText: stepNote.fingeringText
                )
                triggersByTick[onTick, default: []].append(note)
                if offTick > onTick {
                    releasesByTick[offTick, default: []].append(note)
                }
            }
        }

        var eventTicks = Set(triggersByTick.keys).union(releasesByTick.keys).union(restTicks)
        eventTicks = eventTicks.filter { tick in
            triggersByTick[tick]?.isEmpty == false || releasesByTick[tick]?.isEmpty == false || restTicks.contains(tick)
        }
        let sortedTicks = eventTicks.sorted()
        guard sortedTicks.isEmpty == false else { return [] }

        var activeNotesByOccurrenceID: [String: PianoHighlightNote] = [:]
        var guides: [PianoHighlightGuide] = []
        guides.reserveCapacity(sortedTicks.count)

        for (tickIndex, tick) in sortedTicks.enumerated() {
            let releases = releasesByTick[tick] ?? []
            for release in releases {
                activeNotesByOccurrenceID[release.occurrenceID] = nil
            }

            let triggers = (triggersByTick[tick] ?? []).filter { playableRange.contains($0.midiNote) }
            for trigger in triggers {
                activeNotesByOccurrenceID[trigger.occurrenceID] = trigger
            }

            let activeNotes = activeNotesByOccurrenceID.values.sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                if (lhs.staff ?? 0) != (rhs.staff ?? 0) { return (lhs.staff ?? 0) < (rhs.staff ?? 0) }
                if (lhs.voice ?? 0) != (rhs.voice ?? 0) { return (lhs.voice ?? 0) < (rhs.voice ?? 0) }
                return lhs.occurrenceID < rhs.occurrenceID
            }

            let kind: PianoHighlightGuideKind
            if triggers.isEmpty == false {
                kind = .trigger
            } else if releases.isEmpty == false {
                kind = activeNotes.isEmpty ? .gap : .release
            } else {
                kind = .gap
            }

            let nextTick = sortedTicks.indices.contains(tickIndex + 1) ? sortedTicks[tickIndex + 1] : nil
            let durationTicks = nextTick.map { max(0, $0 - tick) }
            let practiceStepIndex = practiceStepIndexByTick[tick]
            let releasedMIDINotes = Set(releases.map(\.midiNote))

            guides.append(PianoHighlightGuide(
                id: guides.count + 1,
                kind: kind,
                tick: tick,
                durationTicks: durationTicks,
                practiceStepIndex: practiceStepIndex,
                activeNotes: activeNotes,
                triggeredNotes: triggers.sorted { $0.midiNote < $1.midiNote },
                releasedMIDINotes: releasedMIDINotes
            ))
        }

        return guides
    }

    static func makeFallbackGuides(from steps: [PracticeStep]) -> [PianoHighlightGuide] {
        steps.enumerated().map { index, step in
            let notes = step.notes.enumerated().map { noteIndex, stepNote in
                PianoHighlightNote(
                    occurrenceID: "fallback-\(index)-\(noteIndex)-\(stepNote.midiNote)",
                    midiNote: stepNote.midiNote,
                    staff: stepNote.staff,
                    voice: nil,
                    velocity: stepNote.velocity,
                    onTick: step.tick + stepNote.onTickOffset,
                    offTick: step.tick + stepNote.onTickOffset,
                    fingeringText: stepNote.fingeringText
                )
            }
            return PianoHighlightGuide(
                id: index + 1,
                kind: .trigger,
                tick: step.tick,
                durationTicks: nil,
                practiceStepIndex: index,
                activeNotes: notes,
                triggeredNotes: notes,
                releasedMIDINotes: []
            )
        }
    }

    private func makeSourceNotesByKey(
        score: MusicXMLScore,
        expressivity: MusicXMLExpressivityOptions
    ) -> [SourceNoteKey: MusicXMLNoteEvent] {
        var result: [SourceNoteKey: MusicXMLNoteEvent] = [:]
        result.reserveCapacity(score.notes.count)

        for note in score.notes {
            guard note.isRest == false else { continue }
            guard note.tieStop == false else { continue }
            if note.isGrace, expressivity.graceEnabled == false { continue }
            guard let midiNote = note.midiNote else { continue }
            let staff = note.staff ?? 1
            let key = SourceNoteKey(midiNote: midiNote, staff: staff, tick: note.tick)
            if result[key] == nil {
                result[key] = note
            }
        }

        return result
    }

    private func makeSpanByKey(_ spans: [MusicXMLNoteSpan]) -> [SpanKey: MusicXMLNoteSpan] {
        var result: [SpanKey: MusicXMLNoteSpan] = [:]
        result.reserveCapacity(spans.count)

        for span in spans {
            let key = SpanKey(midiNote: span.midiNote, staff: span.staff, onTick: span.onTick)
            if let existing = result[key] {
                if span.offTick > existing.offTick {
                    result[key] = span
                }
            } else {
                result[key] = span
            }
        }

        return result
    }
}
