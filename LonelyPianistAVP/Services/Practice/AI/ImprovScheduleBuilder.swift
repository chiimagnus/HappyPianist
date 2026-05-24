import Foundation
import ImprovProtocol

struct ImprovScheduleBuilder {
    func buildSchedule(
        from notes: [ImprovDialogueNote],
        leadInSeconds: TimeInterval = 0.05
    ) -> [PracticeSequencerMIDIEvent] {
        guard notes.isEmpty == false else { return [] }

        var schedule: [PracticeSequencerMIDIEvent] = []
        schedule.reserveCapacity(notes.count * 2)

        for note in notes {
            let start = max(0, note.time + leadInSeconds)
            // A.I. Duet: shorten reply note durations and cap long holds.
            // See: `.github/features/ai-duet-turn-taking/aiexperiments-ai-duet-master/static/src/ai/AI.js`
            let duetDuration = min(4.0, note.duration * 0.9)
            let duration = max(0.05, duetDuration)
            let end = start + duration

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
}
