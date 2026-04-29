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
        let voice: Int
        let tick: Int
    }

    private struct SpanKey: Hashable {
        let midiNote: Int
        let staff: Int
        let voice: Int
        let onTick: Int
    }

    private let playableRange = 21 ... 108

    func buildGuides(input: PianoHighlightGuideBuildInput) -> [PianoHighlightGuide] {
        guard input.steps.isEmpty == false else { return [] }

        let sourceNotesByKey = makeSourceNotesByKey(score: input.score, expressivity: input.expressivity)
        let spanByKey = makeSpanByKey(input.noteSpans)
        let restTicks = Set(input.score.notes.filter(\.isRest).map(\.tick))

        var occurrenceCounter = 0
        var triggersByTick: [Int: [PianoHighlightNote]] = [:]
        var releasesByTick: [Int: [PianoHighlightNote]] = [:]
        var practiceStepIndexByTriggerTick: [Int: Int] = [:]
        practiceStepIndexByTriggerTick.reserveCapacity(input.steps.count)

        for (stepIndex, step) in input.steps.enumerated() {
            for stepNote in step.notes {
                let baseOnTick = step.tick + stepNote.onTickOffset
                let staff = stepNote.staff ?? 1
                let voice = stepNote.voice ?? 1
                let source = sourceNotesByKey[SourceNoteKey(
                    midiNote: stepNote.midiNote,
                    staff: staff,
                    voice: voice,
                    tick: baseOnTick
                )]
                    ?? sourceNotesByKey[SourceNoteKey(
                        midiNote: stepNote.midiNote,
                        staff: staff,
                        voice: voice,
                        tick: step.tick
                    )]
                let attackTicks = source?.attackTicks ?? 0
                let spanOnTickCandidates = [
                    baseOnTick,
                    baseOnTick + attackTicks,
                    step.tick,
                    step.tick + attackTicks,
                ]
                var span: MusicXMLNoteSpan?
                for candidateTick in spanOnTickCandidates {
                    if span != nil { break }
                    span = spanByKey[SpanKey(
                        midiNote: stepNote.midiNote,
                        staff: staff,
                        voice: voice,
                        onTick: candidateTick
                    )]
                }
                let resolvedVoice = source?.voice ?? voice
                let onTick = span?.onTick ?? baseOnTick
                let offTick = max(onTick + 1, span?.offTick ?? (onTick + max(1, source?.durationTicks ?? 1)))
                occurrenceCounter += 1
                let note = PianoHighlightNote(
                    occurrenceID: "h-\(occurrenceCounter)-\(stepNote.midiNote)-\(onTick)-\(staff)-\(resolvedVoice)",
                    midiNote: stepNote.midiNote,
                    staff: stepNote.staff,
                    voice: resolvedVoice,
                    velocity: stepNote.velocity,
                    onTick: onTick,
                    offTick: offTick,
                    fingeringText: stepNote.fingeringText
                )
                triggersByTick[onTick, default: []].append(note)
                if practiceStepIndexByTriggerTick[onTick] == nil {
                    practiceStepIndexByTriggerTick[onTick] = stepIndex
                }
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

            let kind: PianoHighlightGuideKind = if triggers.isEmpty == false {
                .trigger
            } else if releases.isEmpty == false {
                activeNotes.isEmpty ? .gap : .release
            } else {
                .gap
            }

            let nextTick = sortedTicks.indices.contains(tickIndex + 1) ? sortedTicks[tickIndex + 1] : nil
            let durationTicks = nextTick.map { max(0, $0 - tick) }
            let practiceStepIndex = (kind == .trigger) ? practiceStepIndexByTriggerTick[tick] : nil
            let releasedMIDINotes = Set(releases.map(\.midiNote))

            guides.append(PianoHighlightGuide(
                id: guides.count + 1,
                kind: kind,
                tick: tick,
                durationTicks: durationTicks,
                practiceStepIndex: practiceStepIndex,
                activeNotes: activeNotes,
                triggeredNotes: triggers.sorted { lhs, rhs in
                    if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                    if (lhs.staff ?? 0) != (rhs.staff ?? 0) { return (lhs.staff ?? 0) < (rhs.staff ?? 0) }
                    return (lhs.voice ?? 0) < (rhs.voice ?? 0)
                },
                releasedMIDINotes: releasedMIDINotes
            ))
        }

        return guides
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
            let voice = note.voice ?? 1
            let key = SourceNoteKey(midiNote: midiNote, staff: staff, voice: voice, tick: note.tick)
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
            let key = SpanKey(midiNote: span.midiNote, staff: span.staff, voice: span.voice, onTick: span.onTick)
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
