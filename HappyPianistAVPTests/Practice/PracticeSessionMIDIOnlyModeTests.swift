import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
@MainActor
func bluetoothMIDISessionDoesNotInjectAudioRecognition() {
    let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel = { modeID in
        PracticeSessionViewModel(
            pressDetectionService: NoopPressDetectionService(),
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
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    let steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
    session.setSteps(steps, tempoMap: MusicXMLTempoMap(tempoEvents: []))
    session.startGuidingIfReady()

    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 100),
        channel: 1,
        group: 0,
        source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
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
        pressDetectionService: NoopPressDetectionService(),
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

    let steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
    session.setSteps(steps, tempoMap: MusicXMLTempoMap(tempoEvents: []))
    session.startGuidingIfReady()

    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI2(MIDI2InputEvent(
        kind: .noteOn(note: 60, velocity16: 0),
        channel: 1,
        group: 0,
        source: MIDI2InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
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
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    let steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
    session.setSteps(steps, tempoMap: MusicXMLTempoMap(tempoEvents: []))
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
        source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
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
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: inputSource,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    let stepA = PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])
    session.setSteps([stepA], tempoMap: MusicXMLTempoMap(tempoEvents: []))
    session.startGuidingIfReady()
    #expect(inputSource.startCallCount == 1)
    #expect(session.isPracticeInputRunning == false)
    #expect(inputSource.isRunning == false)
    #expect(session.currentStepIndex == 0)

    let stepB = PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 61, staff: 1)])
    session.setSteps([stepB], tempoMap: MusicXMLTempoMap(tempoEvents: []))
    session.startGuidingIfReady()
    #expect(inputSource.startCallCount == 2)
    #expect(session.isPracticeInputRunning)
    #expect(inputSource.isRunning)
    #expect(session.currentStepIndex == 0)

    inputSource.emitMIDI1(MIDI1InputEvent(
        kind: .noteOn(note: 60, velocity: 100),
        channel: 1,
        group: 0,
        source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
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
        source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: "fake"),
        receivedAt: Date(),
        receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime
    ))

    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(session.currentStepIndex == 1)
}

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], tolerance _: Int, at _: Date) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

@MainActor
private final class NoopPracticeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}
