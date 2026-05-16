import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
@MainActor
func bluetoothMIDIFactoryDoesNotInjectAudioRecognition() {
    let mode = BluetoothMIDIPianoMode(makePracticeSessionViewModel: {
        PracticeSessionViewModel(
            pressDetectionService: NoopPressDetectionService(),
            chordAttemptAccumulator: NoopChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
            audioRecognitionService: nil,
            practiceInputEventSource: FakePracticeInputEventSource(),
            audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
            handPianoActivityGate: HandPianoActivityGate()
        )
    })
    let registry = PianoModeRegistryService(modes: [mode])
    let factory = PracticeSessionViewModelFactoryService(
        pianoModeRegistry: registry,
        makeFallbackPracticeSessionViewModel: {
            PracticeSessionViewModel(
                pressDetectionService: NoopPressDetectionService(),
                chordAttemptAccumulator: NoopChordAttemptAccumulator(),
                sleeper: TaskSleeper(),
                sequencerPlaybackService: NoopPracticeSequencerPlaybackService(),
                audioRecognitionService: nil,
                practiceInputEventSource: nil,
                audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
                handPianoActivityGate: HandPianoActivityGate()
            )
        }
    )
    let session = factory.makePracticeSessionViewModel(for: mode.id)

    #expect(session.audioRecognitionService == nil)
    #expect(session.practiceInputEventSource != nil)
}

@Test
@MainActor
func midiOnlyPracticeInputNoteOnAdvancesStep() async throws {
    let inputSource = FakePracticeInputEventSource()
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

    inputSource.emit(PracticeInputEvent(kind: .noteOn(note: 60, velocity: 100), channel: 1, receivedAt: Date(), receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime))

    for _ in 0 ..< 20 {
        await Task.yield()
    }
    #expect(session.currentStepIndex == 1)
}

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], tolerance _: Int, at _: Date) -> Bool {
        false
    }

    func reset() {}
}

@MainActor
private final class NoopPracticeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}
