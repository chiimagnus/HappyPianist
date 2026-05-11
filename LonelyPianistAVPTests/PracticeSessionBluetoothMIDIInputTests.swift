import Foundation
import Testing
@testable import LonelyPianistAVP
import simd

@Test
@MainActor
func guidingStartsBluetoothMIDIWhenPreferred() async {
    UserDefaults.standard.set(Step3PracticeInputSource.bluetoothMIDI.rawValue, forKey: "practiceStep3InputSource")

    let fakeAudio = FakePracticeAudioRecognitionService()
    let fakeBluetooth = FakeBluetoothMIDIPracticeInputService()
    fakeBluetooth.startReturnSourceCount = 1

    let viewModel = makeViewModel(audioRecognitionService: fakeAudio, bluetoothMIDIService: fakeBluetooth)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(fakeBluetooth.startCalls.count == 1)
    #expect(fakeAudio.startCalls.isEmpty)
    #expect(viewModel.activePracticeInputSource == .bluetoothMIDI)
}

@Test
@MainActor
func matchingBluetoothMIDIEventAdvancesStep() async {
    UserDefaults.standard.set(Step3PracticeInputSource.bluetoothMIDI.rawValue, forKey: "practiceStep3InputSource")

    let fakeAudio = FakePracticeAudioRecognitionService()
    let fakeBluetooth = FakeBluetoothMIDIPracticeInputService()
    fakeBluetooth.startReturnSourceCount = 1

    let viewModel = makeViewModel(audioRecognitionService: fakeAudio, bluetoothMIDIService: fakeBluetooth)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeBluetooth.startCalls.first?.generation ?? 0

    fakeBluetooth.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 1.0,
            onsetScore: 1.0,
            isOnset: true,
            timestamp: Date().addingTimeInterval(0.6),
            generation: generation,
            source: .bluetoothMIDI
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func bluetoothMIDIFallsBackToAudioWhenNoSources() async {
    UserDefaults.standard.set(Step3PracticeInputSource.bluetoothMIDI.rawValue, forKey: "practiceStep3InputSource")

    let fakeAudio = FakePracticeAudioRecognitionService()
    let fakeBluetooth = FakeBluetoothMIDIPracticeInputService()
    fakeBluetooth.startReturnSourceCount = 0

    let viewModel = makeViewModel(audioRecognitionService: fakeAudio, bluetoothMIDIService: fakeBluetooth)
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )

    viewModel.startGuidingIfReady()
    await settleTaskQueue()

    #expect(fakeBluetooth.startCalls.count == 1)
    #expect(fakeAudio.startCalls.count == 1)
    #expect(viewModel.activePracticeInputSource == .audio)
    #expect(viewModel.practiceInputWarningMessage?.isEmpty == false)
}

@MainActor
private func makeViewModel(
    audioRecognitionService: PracticeAudioRecognitionServiceProtocol,
    bluetoothMIDIService: BluetoothMIDIPracticeInputServiceProtocol
) -> PracticeSessionViewModel {
    let playbackService = CapturingSequencerPlaybackService()
    return PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        audioRecognitionService: audioRecognitionService,
        bluetoothMIDIInputService: bluetoothMIDIService
    )
}

private func settleTaskQueue(iterations: Int = 4) async {
    for _ in 0 ..< iterations {
        await Task.yield()
    }
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
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> Bool {
        false
    }

    func reset() {}
}

private final class CapturingSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
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

