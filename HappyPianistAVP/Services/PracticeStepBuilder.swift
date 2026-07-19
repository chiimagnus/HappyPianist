import Foundation

protocol PracticeStepBuilderProtocol {
    func buildSteps(from plan: ScorePerformancePlan) -> PracticeStepBuildResult
}

struct PracticeStepBuilder: PracticeStepBuilderProtocol {
    private struct StepNoteKey: Hashable {
        let midiNote: Int
        let staff: Int
        let voice: Int
    }

    private struct StepNoteValue {
        let handAssignment: ScoreHandAssignment
        let velocity: UInt8
        let fingerings: [MusicXMLFingering]
        var sourceNoteIDs: [MusicXMLSourceNoteID]
    }

    private let playableRange = 21 ... 108

    func buildSteps(from plan: ScorePerformancePlan) -> PracticeStepBuildResult {
        var grouped: [Int: [StepNoteKey: StepNoteValue]] = [:]
        var unsupportedNoteCount = 0

        for event in plan.noteEvents {
            guard playableRange.contains(event.midiNote) else {
                unsupportedNoteCount += 1
                continue
            }

            let key = StepNoteKey(midiNote: event.midiNote, staff: event.staff, voice: event.voice)
            var notesAtTick = grouped[event.performedOnTick] ?? [:]
            if var existing = notesAtTick[key] {
                var existingIDs = Set(existing.sourceNoteIDs)
                for sourceNoteID in event.contributingSourceNoteIDs where existingIDs.insert(sourceNoteID).inserted {
                    existing.sourceNoteIDs.append(sourceNoteID)
                }
                notesAtTick[key] = existing
            } else {
                notesAtTick[key] = StepNoteValue(
                    handAssignment: event.handAssignment,
                    velocity: event.velocity,
                    fingerings: event.fingerings,
                    sourceNoteIDs: event.contributingSourceNoteIDs
                )
            }
            grouped[event.performedOnTick] = notesAtTick
        }

        let steps = grouped.keys.sorted().map { tick in
            let notesMap = grouped[tick] ?? [:]
            let notes = notesMap.keys.sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                if lhs.staff != rhs.staff { return lhs.staff < rhs.staff }
                return lhs.voice < rhs.voice
            }.map { key in
                let entry = notesMap[key]
                return PracticeStepNote(
                    midiNote: key.midiNote,
                    staff: key.staff,
                    voice: key.voice,
                    velocity: entry?.velocity ?? 96,
                    fingerings: entry?.fingerings ?? [],
                    sourceNoteIDs: entry?.sourceNoteIDs ?? [],
                    handAssignment: entry?.handAssignment ?? .unknown
                )
            }
            return PracticeStep(tick: tick, notes: notes)
        }

        return PracticeStepBuildResult(steps: steps, unsupportedNoteCount: unsupportedNoteCount)
    }
}
