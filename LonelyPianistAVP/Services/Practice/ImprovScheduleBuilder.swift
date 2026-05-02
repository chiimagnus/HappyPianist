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
            let duration = max(0.05, note.duration)
            let end = max(start, note.time + duration + leadInSeconds)

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

        return schedule.sorted { lhs, rhs in
            if lhs.timeSeconds != rhs.timeSeconds { return lhs.timeSeconds < rhs.timeSeconds }
            if eventPriority(lhs.kind) != eventPriority(rhs.kind) {
                return eventPriority(lhs.kind) < eventPriority(rhs.kind)
            }
            return tieBreaker(lhs.kind) < tieBreaker(rhs.kind)
        }
    }

    private func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
            case .controlChange:
                0
            case .noteOff:
                1
            case .noteOn:
                2
        }
    }

    private func tieBreaker(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
            case let .controlChange(controller, value):
                Int(controller) * 256 + Int(value)
            case let .noteOff(midi):
                midi
            case let .noteOn(midi, velocity):
                midi * 256 + Int(velocity)
        }
    }
}
