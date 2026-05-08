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
                PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .noteOn(midi: midi, velocity: UInt8(clamping: velocity))
                )
            case let .noteOff(midi):
                PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .noteOff(midi: midi)
                )
            }
        }
    }

    func buildSequence(from take: RecordingTake) throws -> PracticeSequencerSequence {
        let schedule = makeMIDISchedule(from: take)
        return try builder.buildSequence(from: schedule)
    }
}
