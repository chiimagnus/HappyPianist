import Foundation

protocol PracticeStepBuilderProtocol {
    func buildSteps(from score: MusicXMLScore) -> PracticeStepBuildResult
}

struct PracticeStepBuilder: PracticeStepBuilderProtocol {
    private let playableRange = 21...108

    func buildSteps(from score: MusicXMLScore) -> PracticeStepBuildResult {
        var grouped: [Int: [Int: Int?]] = [:] // tick -> midi -> staff
        var unsupportedNoteCount = 0

        for noteEvent in score.notes {
            if noteEvent.isRest {
                continue
            }

            guard let midiNote = noteEvent.midiNote else {
                continue
            }

            guard playableRange.contains(midiNote) else {
                unsupportedNoteCount += 1
                continue
            }

            var map = grouped[noteEvent.tick] ?? [:]
            if map[midiNote] == nil {
                map[midiNote] = noteEvent.staff
            }
            grouped[noteEvent.tick] = map
        }

        let steps = grouped.keys.sorted().map { tick in
            let notesMap = grouped[tick] ?? [:]
            let notes = notesMap.keys.sorted().map { midiNote in
                PracticeStepNote(midiNote: midiNote, staff: notesMap[midiNote] ?? nil)
            }
            return PracticeStep(tick: tick, notes: notes)
        }

        return PracticeStepBuildResult(steps: steps, unsupportedNoteCount: unsupportedNoteCount)
    }
}
