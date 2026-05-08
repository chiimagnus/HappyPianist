import Foundation

nonisolated struct RecordingTakeSequenceAdapter {
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
            }
        }
    }

    func buildSequence(from take: RecordingTake) throws -> PracticeSequencerSequence {
        let schedule = makeMIDISchedule(from: take)
        return try builder.buildSequence(from: schedule)
    }
}
