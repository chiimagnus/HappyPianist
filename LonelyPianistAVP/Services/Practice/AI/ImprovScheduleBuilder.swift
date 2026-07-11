import Foundation

struct ImprovScheduleBuilder {
    func buildSchedule(
        from notes: [ImprovDialogueNote],
        leadInSeconds: TimeInterval = 0.05
    ) -> [PracticeSequencerMIDIEvent] {
        let events = notes.map { note in
            ImprovEvent.note(note: note.note, velocity: note.velocity, time: note.time, duration: note.duration)
        }
        return buildSchedule(from: events, leadInSeconds: leadInSeconds)
    }

    func buildSchedule(
        from events: [ImprovEvent],
        leadInSeconds: TimeInterval = 0.05
    ) -> [PracticeSequencerMIDIEvent] {
        guard events.isEmpty == false else { return [] }

        var schedule: [PracticeSequencerMIDIEvent] = []
        schedule.reserveCapacity(events.count * 2)

        for event in events {
            switch event.type {
            case .note:
                guard let note = event.note, let velocity = event.velocity, let duration = event.duration else { continue }

                let start = max(0, event.time + leadInSeconds)
                // A.I. Duet: shorten reply note durations and cap long holds.
                // See: `.github/features/ai-duet-turn-taking/aiexperiments-ai-duet-master/static/src/ai/AI.js`
                let duetDuration = min(4.0, duration * 0.9)
                let clampedDuration = max(0.05, duetDuration)
                let end = start + clampedDuration

                schedule.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: start,
                        kind: .noteOn(midi: note, velocity: UInt8(clamping: velocity))
                    )
                )
                schedule.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: end,
                        kind: .noteOff(midi: note)
                    )
                )

            case .cc:
                guard let controller = event.controller, let value = event.value else { continue }
                guard Self.allowedControllers.contains(controller) else { continue }

                schedule.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.time + leadInSeconds),
                        kind: .controlChange(controller: UInt8(clamping: controller), value: UInt8(clamping: value))
                    )
                )
            }
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
        case .programChange, .pitchBend, .channelPressure, .polyPressure:
            1
        case .noteOff:
            2
        case .noteOn:
            3
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
        case let .pitchBend(value):
            1_000_000 + Int(value)
        case let .programChange(program):
            2_000_000 + Int(program)
        case let .channelPressure(value):
            3_000_000 + Int(value)
        case let .polyPressure(midi, value):
            4_000_000 + midi * 256 + Int(value)
        }
    }

    private static let allowedControllers: Set<Int> = [7, 11, 64]
}
