import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func midiRecordingAdapterRecordsNoteEventsAndClosesOpenNotes() {
    var recorder = RecordingTakeRecorder()
    let adapter = MIDIRecordingAdapter()

    recorder.start(now: 1000)

    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 100),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 1001.0
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 1001.5
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 1002.0, createdAt: Date(timeIntervalSince1970: 0))

    #expect(take.events.contains(where: { $0.time == 1.0 && $0.kind == .noteOn(midi: 60, velocity: 100) }))
    #expect(take.events.contains(where: { $0.time == 1.5 && $0.kind == .noteOff(midi: 60) }))
}

@Test
func midiRecordingAdapterConvertsChannelVoiceEventsIntoTakeEvents() {
    var recorder = RecordingTakeRecorder()
    let adapter = MIDIRecordingAdapter()

    recorder.start(now: 2000)

    adapter.record(
        event: MIDI1InputEvent(
            kind: .controlChange(controller: 64, value: 127),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 2000.2
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI1InputEvent(
            kind: .pitchBend(value: 8192),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 2000.3
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI1InputEvent(
            kind: .programChange(program: 10),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 2000.4
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 2001.0, createdAt: Date(timeIntervalSince1970: 0))

    #expect(take.events.contains(where: { $0.kind == .controlChange(controller: 64, value: 127) }))
    #expect(take.events.contains(where: { $0.kind == .pitchBend(value: 8192) }))
    #expect(take.events.contains(where: { $0.kind == .programChange(program: 10) }))

    let schedule = RecordingTakeSequenceAdapter().makeMIDISchedule(from: take)
    #expect(schedule.contains(where: { $0.kind == .controlChange(controller: 64, value: 127) }))
    #expect(schedule.contains(where: { $0.kind == .pitchBend(value: 8192) }))
    #expect(schedule.contains(where: { $0.kind == .programChange(program: 10) }))
}

@Test
func repeatedNoteOnForSamePitchGeneratesClosingNoteOff() {
    var recorder = RecordingTakeRecorder()
    let adapter = MIDIRecordingAdapter()

    recorder.start(now: 3000)

    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 100),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 3000.1
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 100),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 3000.3
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 3000.5, createdAt: Date(timeIntervalSince1970: 0))
    let eventsAt0_3 = take.events.filter { abs($0.time - 0.3) < 0.0001 }

    #expect(eventsAt0_3.contains(where: { $0.kind == .noteOff(midi: 60) }))
    #expect(eventsAt0_3.contains(where: { $0.kind == .noteOn(midi: 60, velocity: 100) }))
}
