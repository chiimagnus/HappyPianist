import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func midiRecordingAdapterRecordsNoteEventsAndClosesOpenNotes() {
    var recorder = RecordingTakeRecorder()
    var adapter = MIDIRecordingAdapter()

    recorder.start(now: 1000)

    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 100),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
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
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 1001.5
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 1002.0, createdAt: Date(timeIntervalSince1970: 0))

    let hasNoteOn = take.events.contains { $0.time == 1.0 && $0.kind == .noteOn(midi: 60, velocity: 100) }
    #expect(hasNoteOn)
    let hasNoteOff = take.events.contains { $0.time == 1.5 && $0.kind == .noteOff(midi: 60) }
    #expect(hasNoteOff)
}

@Test
func midiRecordingAdapterConvertsChannelVoiceEventsIntoTakeEvents() {
    var recorder = RecordingTakeRecorder()
    var adapter = MIDIRecordingAdapter()

    recorder.start(now: 2000)

    adapter.record(
        event: MIDI1InputEvent(
            kind: .controlChange(controller: 64, value: 127),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
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
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
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
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 2000.4
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 2001.0, createdAt: Date(timeIntervalSince1970: 0))

    let hasCC64 = take.events.contains { $0.kind == .controlChange(controller: 64, value: 127) }
    #expect(hasCC64)
    let hasPitchBend = take.events.contains { $0.kind == .pitchBend(value: 8192) }
    #expect(hasPitchBend)
    let hasProgram = take.events.contains { $0.kind == .programChange(program: 10) }
    #expect(hasProgram)

    let schedule = RecordingTakeSequenceAdapter().makeMIDISchedule(from: take)
    let scheduleHasCC64 = schedule.contains { $0.kind == .controlChange(controller: 64, value: 127) }
    #expect(scheduleHasCC64)
    let scheduleHasPitchBend = schedule.contains { $0.kind == .pitchBend(value: 8192) }
    #expect(scheduleHasPitchBend)
    let scheduleHasProgram = schedule.contains { $0.kind == .programChange(program: 10) }
    #expect(scheduleHasProgram)
}

@Test
func repeatedNoteOnForSamePitchGeneratesClosingNoteOff() {
    var recorder = RecordingTakeRecorder()
    var adapter = MIDIRecordingAdapter()

    recorder.start(now: 3000)

    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 100),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
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
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
            receivedAt: Date(),
            receivedAtUptimeSeconds: 3000.3
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 3000.5, createdAt: Date(timeIntervalSince1970: 0))
    let eventsAt0_3 = take.events.filter { abs($0.time - 0.3) < 0.0001 }

    let has0_3NoteOff = eventsAt0_3.contains { $0.kind == .noteOff(midi: 60) }
    #expect(has0_3NoteOff)
    let has0_3NoteOn = eventsAt0_3.contains { $0.kind == .noteOn(midi: 60, velocity: 100) }
    #expect(has0_3NoteOn)
}

@Test
func midiRecordingAdapterAllNotesOffClosesOpenNotesAtDiscontinuity() {
    var recorder = RecordingTakeRecorder()
    var adapter = MIDIRecordingAdapter()
    let source = MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake")

    recorder.start(now: 4000)
    adapter.record(
        event: MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 100),
            channel: 1,
            group: 0,
            source: source,
            receivedAt: .now,
            receivedAtUptimeSeconds: 4000.1
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI1InputEvent(
            kind: .controlChange(controller: 123, value: 0),
            channel: 1,
            group: 0,
            source: source,
            receivedAt: .now,
            receivedAtUptimeSeconds: 4000.4
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 4001, createdAt: Date(timeIntervalSince1970: 0))

    #expect(take.events.contains { abs($0.time - 0.4) < 0.0001 && $0.kind == .noteOff(midi: 60) })
    #expect(take.events.contains { $0.kind == .controlChange(controller: 123, value: 0) })
    #expect(take.events.count(where: { $0.kind == .noteOff(midi: 60) }) == 1)
}

@Test
func midiRecordingKeepsRoutesIndependentAndPreservesMIDI2Evidence() {
    var recorder = RecordingTakeRecorder()
    var adapter = MIDIRecordingAdapter()
    let source = MIDIInputSource(identifier: .endpointUniqueID(42), endpointName: "fake")

    recorder.start(now: 5000)
    adapter.beginRecording()
    adapter.record(
        event: MIDI2InputEvent(
            kind: .noteOn(note: 60, velocity16: 0x1234),
            channel: 1,
            group: 3,
            source: source,
            receivedAt: .now,
            receivedAtUptimeSeconds: 5000.1,
            sourceTimestamp: PerformanceSourceTimestamp(clockID: "core-midi-host", seconds: 50)
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI2InputEvent(
            kind: .noteOn(note: 60, velocity16: 0x5678),
            channel: 2,
            group: 3,
            source: source,
            receivedAt: .now,
            receivedAtUptimeSeconds: 5000.2
        ),
        into: &recorder
    )
    adapter.record(
        event: MIDI2InputEvent(
            kind: .noteOff(note: 60, velocity16: 0xABCD),
            channel: 1,
            group: 3,
            source: source,
            receivedAt: .now,
            receivedAtUptimeSeconds: 5000.4
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 5001, createdAt: Date(timeIntervalSince1970: 0))
    let channel1Off = take.events.first {
        $0.kind == .noteOff(midi: 60) && $0.observation?.channel == 1
    }
    let channel2Off = take.events.first {
        $0.kind == .noteOff(midi: 60) && $0.observation?.channel == 2
    }
    let channel1On = take.events.first {
        $0.kind == .noteOn(midi: 60, velocity: MIDI2ValueMapping.value16To7Bit(0x1234))
    }

    #expect(abs((channel1Off?.time ?? 0) - 0.4) < 0.0001)
    #expect(abs((channel2Off?.time ?? 0) - 1) < 0.0001)
    #expect(channel1On?.observation?.source.id == "endpoint:42")
    #expect(channel1On?.observation?.group == 3)
    #expect(channel1On?.observation?.timing.source?.clockID == "core-midi-host")
    if case let .noteOn(_, velocity)? = channel1On?.observation?.event {
        #expect(velocity?.rawValue == UInt32(0x1234) * 65_537)
    } else {
        Issue.record("MIDI 2 note-on evidence was not retained")
    }
    if case let .noteOff(_, releaseVelocity)? = channel1Off?.observation?.event {
        #expect(releaseVelocity?.rawValue == UInt32(0xABCD) * 65_537)
    } else {
        Issue.record("MIDI 2 release evidence was not retained")
    }
    #expect(take.metadata.inputSources == [RecordingInputSourceDescriptor(
        kind: .midi2,
        id: "endpoint:42",
        capabilities: .midi
    )])
}

@Test
func allNotesOffOnlyClosesItsSourceGroupAndChannel() {
    var recorder = RecordingTakeRecorder()
    var adapter = MIDIRecordingAdapter()
    let source = MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake")

    recorder.start(now: 6000)
    for channel in [1, 2] {
        adapter.record(
            event: MIDI1InputEvent(
                kind: .noteOn(note: 60, velocity: 100),
                channel: channel,
                group: 0,
                source: source,
                receivedAt: .now,
                receivedAtUptimeSeconds: 6000.1
            ),
            into: &recorder
        )
    }
    adapter.record(
        event: MIDI1InputEvent(
            kind: .controlChange(controller: 123, value: 0),
            channel: 1,
            group: 0,
            source: source,
            receivedAt: .now,
            receivedAtUptimeSeconds: 6000.3
        ),
        into: &recorder
    )

    let take = recorder.stop(now: 6001, createdAt: Date(timeIntervalSince1970: 0))
    let noteOffs = take.events.filter { $0.kind == .noteOff(midi: 60) }
    #expect(noteOffs.count == 2)
    #expect(noteOffs.contains { abs($0.time - 0.3) < 0.0001 && $0.observation?.channel == 1 })
    #expect(noteOffs.contains { abs($0.time - 1) < 0.0001 && $0.observation?.channel == 2 })
}

@Test
@MainActor
func keyContactRecordingCoalescesMultipleFingersOnTheSameMIDIKey() throws {
    var nowUptime: TimeInterval = 0
    var recordedTakes: [RecordingTake] = []
    let state = MIDIRecordingState(
        nowUptimeSeconds: { nowUptime },
        nowDate: { Date(timeIntervalSince1970: nowUptime) },
        onStateChanged: { _ in },
        onTakeRecorded: { recordedTakes.append($0) }
    )
    state.startRecordingIfPossible(canRecord: true)

    state.recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: false,
        isVirtualPianoEnabled: true,
        observations: [
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .started,
                sequence: 1,
                timestamp: .init(seconds: 0.1),
                resolvedVelocity: 37
            ),
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .started,
                hand: .left,
                sequence: 2,
                timestamp: .init(seconds: 0.2),
                resolvedVelocity: 91
            ),
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .ended,
                sequence: 1,
                timestamp: .init(seconds: 0.3)
            ),
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .ended,
                hand: .left,
                sequence: 2,
                timestamp: .init(seconds: 0.4)
            ),
        ]
    )
    nowUptime = 0.5
    state.stopRecordingIfNeeded()

    let take = try #require(recordedTakes.first)
    #expect(take.events.map(\.kind) == [
        .noteOn(midi: 60, velocity: 37),
        .noteOff(midi: 60),
    ])
    #expect(take.events.map(\.time) == [0.1, 0.4])
}

@Test
@MainActor
func observationReplayDrivesMatcherRecorderAndLegacyCodec() throws {
    let fixture = try PerformanceObservationReplayFixtureLoader().load()
    #expect(fixture.observations.map(\.source.kind).contains(.midi1))
    #expect(fixture.observations.map(\.source.kind).contains(.midi2))
    #expect(fixture.observations.map(\.source.kind).contains(.targetAudio))
    #expect(zip(fixture.observations, fixture.observations.dropFirst()).contains {
        $0.0.timing.host > $0.1.timing.host
    })
    #expect(fixture.observations.first?.timing.mapping?.offsetSeconds == 0.48)
    #expect(fixture.observations.contains {
        if case .controller = $0.event { true } else { false }
    })

    let matcher = MIDIPracticeStepMatcher()
    matcher.reset(
        stepIndex: 0,
        expectedNotes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]
    )
    var matcherCursor = PerformanceInputReplayCursor(events: fixture.replayEvents)
    var matchResults: [StepAttemptMatchResult] = []
    matcherCursor.replay { event in
        if let result = matcher.register(event.payload) {
            matchResults.append(result)
        }
    }
    #expect(matchResults.first == .matched)

    var recorder = RecordingTakeRecorder()
    recorder.start(now: 9.8)
    var recorderCursor = PerformanceInputReplayCursor(events: fixture.replayEvents)
    recorderCursor.replay { recorder.record($0.payload) }
    let take = recorder.stop(now: 10.6, createdAt: Date(timeIntervalSince1970: 0))

    #expect(take.events.count == 6)
    #expect(take.events.allSatisfy { $0.observation != nil })
    #expect(take.metadata.inputSources.map(\.kind) == [.midi1, .midi2])
    #expect(take.metadata.clockMapping?.sourceClockID == "core-midi-host")
    #expect(take.metadata.calibrationVersion == "midi-latency-v1")
    #expect(fixture.legacyTake.metadata.provenance == .legacy)
    #expect(fixture.legacyTake.events.map(\.kind) == [
        .noteOn(midi: 55, velocity: 72),
        .noteOff(midi: 55),
    ])
    #expect(fixture.legacyTake.events.allSatisfy { $0.observation == nil })
}
