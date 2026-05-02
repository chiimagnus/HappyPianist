import Foundation

nonisolated struct ImprovScheduleBuilder {
    func buildSchedule(
        from notes: [ImprovDialogueNote],
        leadInSeconds: TimeInterval = 0.05
    ) -> [PracticeSequencerMIDIEvent] {
        guard notes.isEmpty == false else { return [] }

        var schedule: [PracticeSequencerMIDIEvent] = []
        schedule.reserveCapacity(notes.count * 2)

        for note in notes {
            let start = max(0, note.time + leadInSeconds)
            let end = max(start, note.time + note.duration + leadInSeconds)

            schedule.append(
                PracticeSequencerMIDIEvent(
                    timeSeconds: start,
                    kind: .noteOn(midi: note.note, velocity: UInt8(clamping: note.velocity))
                )
            )
            schedule.append(
                PracticeSequencerMIDIEvent(
                    timeSeconds: end,
                    kind: .noteOff(midi: note.note)
                )
            )
        }

        return schedule
    }
}

