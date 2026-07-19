import Foundation

struct PianoHighlightGuideBuilderService {
    private let playableRange = 21 ... 108

    func buildGuides(plan: ScorePerformancePlan) -> [PianoHighlightGuide] {
        let playableEvents = plan.noteEvents.filter { playableRange.contains($0.midiNote) }
        guard playableEvents.isEmpty == false else { return [] }
        let stepIndexByTick = Dictionary(uniqueKeysWithValues: Set(playableEvents.map(\.performedOnTick))
            .sorted()
            .enumerated()
            .map { ($0.element, $0.offset) })
        var triggersByTick: [Int: [PianoHighlightNote]] = [:]
        var releasesByTick: [Int: [PianoHighlightNote]] = [:]

        for event in playableEvents {
            let onTick = event.performedOnTick
            let offTick = max(onTick + 1, event.performedOffTick)
            let note = PianoHighlightNote(
                occurrenceID: event.id.description,
                midiNote: event.midiNote,
                staff: event.staff,
                voice: event.voice,
                velocity: event.velocity,
                onTick: onTick,
                offTick: offTick,
                fingerings: event.fingerings,
                handAssignment: event.handAssignment
            )
            triggersByTick[onTick, default: []].append(note)
            releasesByTick[offTick, default: []].append(note)
        }

        let eventTicks = Set(triggersByTick.keys).union(releasesByTick.keys).sorted()
        var activeNotesByOccurrenceID: [String: PianoHighlightNote] = [:]
        var guides: [PianoHighlightGuide] = []
        guides.reserveCapacity(eventTicks.count)

        for (tickIndex, tick) in eventTicks.enumerated() {
            let releases = releasesByTick[tick] ?? []
            for release in releases {
                activeNotesByOccurrenceID[release.occurrenceID] = nil
            }

            let triggers = sorted(triggersByTick[tick] ?? [])
            for trigger in triggers {
                activeNotesByOccurrenceID[trigger.occurrenceID] = trigger
            }

            let activeNotes = sorted(Array(activeNotesByOccurrenceID.values))
            let kind: PianoHighlightGuideKind = if triggers.isEmpty == false {
                .trigger
            } else if releases.isEmpty == false {
                activeNotes.isEmpty ? .gap : .release
            } else {
                .gap
            }
            let nextTick = eventTicks.indices.contains(tickIndex + 1) ? eventTicks[tickIndex + 1] : nil

            guides.append(PianoHighlightGuide(
                id: guides.count + 1,
                kind: kind,
                tick: tick,
                durationTicks: nextTick.map { max(0, $0 - tick) },
                practiceStepIndex: kind == .trigger ? stepIndexByTick[tick] : nil,
                activeNotes: activeNotes,
                triggeredNotes: triggers,
                releasedMIDINotes: Set(releases.map(\.midiNote))
                    .subtracting(activeNotes.map(\.midiNote))
            ))
        }

        return guides
    }

    private func sorted(_ notes: [PianoHighlightNote]) -> [PianoHighlightNote] {
        notes.sorted { lhs, rhs in
            if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
            if (lhs.staff ?? 0) != (rhs.staff ?? 0) { return (lhs.staff ?? 0) < (rhs.staff ?? 0) }
            if (lhs.voice ?? 0) != (rhs.voice ?? 0) { return (lhs.voice ?? 0) < (rhs.voice ?? 0) }
            return lhs.occurrenceID < rhs.occurrenceID
        }
    }
}
