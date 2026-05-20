import Foundation

struct RecordingTakeSequenceAdapter {
    private let builder: PracticeSequencerSequenceBuilder

    init(builder: PracticeSequencerSequenceBuilder = PracticeSequencerSequenceBuilder()) {
        self.builder = builder
    }

    func makeMIDISchedule(from take: RecordingTake) -> [PracticeSequencerMIDIEvent] {
        take.events.map { event in
            switch event.kind {
                case let .noteOn(midi, velocity):
                    let clampedMIDINote = max(0, min(127, midi))
                    let clampedVelocity = max(0, min(127, velocity))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .noteOn(midi: clampedMIDINote, velocity: UInt8(clampedVelocity))
                    )
                case let .noteOff(midi):
                    let clampedMIDINote = max(0, min(127, midi))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .noteOff(midi: clampedMIDINote)
                    )
                case let .controlChange(controller, value):
                    let clampedController = max(0, min(127, controller))
                    let clampedValue = max(0, min(127, value))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .controlChange(controller: UInt8(clampedController), value: UInt8(clampedValue))
                    )
                case let .pitchBend(value):
                    let clampedValue = max(0, min(16383, value))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .pitchBend(value: UInt16(clampedValue))
                    )
                case let .programChange(program):
                    let clampedProgram = max(0, min(127, program))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .programChange(program: UInt8(clampedProgram))
                    )
                case let .channelPressure(value):
                    let clampedValue = max(0, min(127, value))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .channelPressure(value: UInt8(clampedValue))
                    )
                case let .polyPressure(midi, value):
                    let clampedMIDINote = max(0, min(127, midi))
                    let clampedValue = max(0, min(127, value))
                    return PracticeSequencerMIDIEvent(
                        timeSeconds: event.time,
                        kind: .polyPressure(midi: clampedMIDINote, value: UInt8(clampedValue))
                    )
            }
        }
    }

    func buildSequence(from take: RecordingTake) throws -> PracticeSequencerSequence {
        let schedule = makeMIDISchedule(from: take)
        return try builder.buildSequence(from: schedule)
    }
}
