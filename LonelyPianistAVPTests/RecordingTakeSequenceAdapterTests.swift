@testable import LonelyPianistAVP
import Testing

@Test
func adapterProducesNonEmptyScheduleFromTake() {
    let take = RecordingTake(
        name: "Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let schedule = adapter.makeMIDISchedule(from: take)

    #expect(schedule.count == 2)
    #expect(schedule[0].kind == .noteOn(midi: 60, velocity: 90))
    #expect(schedule[1].kind == .noteOff(midi: 60))
}

@Test
func adapterBuildsNonEmptySequence() throws {
    let take = RecordingTake(
        name: "Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let sequence = try adapter.buildSequence(from: take)

    #expect(sequence.midiData.isEmpty == false)
    #expect(sequence.durationSeconds > 0)
}

@Test
func adapterClampsVelocityToMIDIRange() {
    let take = RecordingTake(
        name: "Test",
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 200)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )
    let adapter = RecordingTakeSequenceAdapter()
    let schedule = adapter.makeMIDISchedule(from: take)

    if case let .noteOn(_, velocity) = schedule[0].kind {
        #expect(velocity == 127)
    } else {
        Issue.record("Expected noteOn")
    }
}

@Test
func adapterHandlesEmptyTake() throws {
    let take = RecordingTake(name: "Empty", events: [])
    let adapter = RecordingTakeSequenceAdapter()
    let schedule = adapter.makeMIDISchedule(from: take)

    #expect(schedule.isEmpty)
}
