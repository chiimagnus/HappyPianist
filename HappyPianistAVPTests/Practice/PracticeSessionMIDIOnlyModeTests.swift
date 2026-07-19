import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
@MainActor
func bluetoothMIDISessionDoesNotInjectAudioRecognition() {
    let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel = { modeID in
        PracticeSessionViewModel(
            chordAttemptAccumulator: NoopChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
            audioRecognitionService: nil,
            practiceInputEventSource: modeID == PianoModeID.bluetoothMIDI.rawValue
                ? FakeProtocolSeparatedPracticeInputEventSource()
                : nil,
            audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
            handPianoActivityGate: HandPianoActivityGate()
        )
    }

    let session = makePracticeSessionViewModel(PianoModeID.bluetoothMIDI.rawValue)

    #expect(session.audioRecognitionService == nil)
    #expect(session.practiceInputEventSource != nil)
}

@Test
@MainActor
func midiOnlyPracticeInputNoteOnAdvancesStep() async {
    let inputSource = FakeProtocolSeparatedPracticeInputEventSource()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    session.installTestPerformanceNotes([
        TestScorePerformanceNote(midiNote: 60, onTick: 0),
        TestScorePerformanceNote(midiNote: 62, onTick: 240),
    ])
    session.startGuidingIfReady()

    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 100),
        channel: 1,
        group: 0,
        source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
        receivedAt: Date(),
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(session.currentStepIndex == 1)
}

@Test
@MainActor
func midiOnlyPracticeInputMIDI2NoteOnAdvancesStepEvenWithZeroVelocity() async {
    let inputSource = FakeProtocolSeparatedPracticeInputEventSource()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    #expect(inputSource.midi1StreamCallCount == 1)
    #expect(inputSource.midi2StreamCallCount == 1)

    session.installTestPerformanceNotes([
        TestScorePerformanceNote(midiNote: 60, onTick: 0),
        TestScorePerformanceNote(midiNote: 62, onTick: 240),
    ])
    session.startGuidingIfReady()

    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI2(MIDI2InputEvent(
        kind: .noteOn(note: 60, velocity16: 0),
        channel: 1,
        group: 0,
        source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
        receivedAt: Date(),
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(session.currentStepIndex == 1)
}

@Test
@MainActor
func midiOnlyPracticeExitStopsInputAndDoesNotAdvanceStepAfterTeardown() async {
    let inputSource = FakeProtocolSeparatedPracticeInputEventSource()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    session.installTestPerformanceNotes([
        TestScorePerformanceNote(midiNote: 60, onTick: 0),
        TestScorePerformanceNote(midiNote: 62, onTick: 240),
    ])
    session.startGuidingIfReady()

    #expect(inputSource.startCallCount == 1)
    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    session.shutdown()

    #expect(inputSource.stopCallCount == 1)
    #expect(inputSource.isRunning == false)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 100),
        channel: 1,
        group: 0,
        source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
        receivedAt: Date(),
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    for _ in 0 ..< 20 {
        await Task.yield()
    }

    #expect(session.currentStepIndex == 0)
}

@Test
@MainActor
func midiOnlyPracticeInputStartFailureThenReplacingSameIndexStepResetsMatcherExpectedNotes() async {
    let inputSource = FakeProtocolSeparatedPracticeInputEventSource()
    inputSource.shouldFailNextStart = true
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    session.installTestPerformanceNotes([TestScorePerformanceNote(midiNote: 60, onTick: 0)])
    session.startGuidingIfReady()
    #expect(inputSource.startCallCount == 1)
    #expect(session.isPracticeInputRunning == false)
    #expect(inputSource.isRunning == false)
    #expect(session.currentStepIndex == 0)

    session.installTestPerformanceNotes([TestScorePerformanceNote(midiNote: 61, onTick: 0)])
    session.startGuidingIfReady()
    #expect(inputSource.startCallCount == 2)
    #expect(session.isPracticeInputRunning)
    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 100),
        channel: 1,
        group: 0,
        source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
        receivedAt: Date(),
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 61, velocity: 100),
        channel: 1,
        group: 0,
        source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "fake"),
        receivedAt: Date(),
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(session.currentStepIndex == 1)
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], at _: PerformanceMonotonicInstant) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}
