import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
@MainActor
func manualReplayBlocksGestureAdvance() async {
    let sleeper = PendingManualReplaySleeper()
    let playbackService = ManualReplaySequencerPlaybackService(currentSeconds: 0)
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: ManualReplayConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: ManualReplayAlwaysMatchAccumulator(),
        sleeper: sleeper,
        sequencerPlaybackService: playbackService,
        manualAdvanceModeProvider: { .measure }
    )
    viewModel.setSteps(makeReplaySteps(), tempoMap: makeReplayTempoMap(), measureSpans: makeReplayMeasures())
    viewModel.applyKeyboardGeometry(makeReplayKeyboardGeometry(), calibration: makeReplayCalibration())
    viewModel.startGuidingIfReady()
    viewModel.replayCurrentUnit()
    await Task.yield()

    let before = viewModel.currentStepIndex
    _ = viewModel.handleFingerTipPositions(["thumb": SIMD3<Float>(0, 0, 0)])

    #expect(viewModel.isManualReplayPlaying)
    #expect(viewModel.currentStepIndex == before)

    viewModel.resetSession()
}

@Test
@MainActor
func manualReplayBlocksAudioRecognitionAdvance() async {
    let sleeper = PendingManualReplaySleeper()
    let audioRecognitionService = FakePracticeAudioRecognitionService()
    let playbackService = ManualReplaySequencerPlaybackService(currentSeconds: 0)
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: ManualReplayNoopPressDetectionService(),
        chordAttemptAccumulator: ManualReplayAlwaysMatchAccumulator(),
        sleeper: sleeper,
        sequencerPlaybackService: playbackService,
        audioRecognitionService: audioRecognitionService,
        manualAdvanceModeProvider: { .measure }
    )
    viewModel.setSteps(makeReplaySteps(), tempoMap: makeReplayTempoMap(), measureSpans: makeReplayMeasures())
    viewModel.startGuidingIfReady()
    await Task.yield()
    viewModel.replayCurrentUnit()
    await Task.yield()

    let before = viewModel.currentStepIndex
    audioRecognitionService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 1,
            onsetScore: 1,
            isOnset: true,
            timestamp: Date(),
            generation: viewModel.audioRecognitionGenerationForTesting,
            source: .audio
        )
    )
    await Task.yield()

    #expect(viewModel.isManualReplayPlaying)
    #expect(viewModel.currentStepIndex == before)

    viewModel.resetSession()
}

@Test
@MainActor
func completedManualReplayReturnsProgressToMeasureStart() async {
    let playbackService = ManualReplaySequencerPlaybackService(currentSeconds: 99)
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: ManualReplayNoopPressDetectionService(),
        chordAttemptAccumulator: ManualReplayAlwaysMatchAccumulator(),
        sleeper: ImmediateManualReplaySleeper(),
        sequencerPlaybackService: playbackService,
        manualAdvanceModeProvider: { .measure }
    )
    viewModel.setSteps(makeReplaySteps(), tempoMap: makeReplayTempoMap(), measureSpans: makeReplayMeasures())
    viewModel.startGuidingIfReady()
    viewModel.currentStepIndex = 1
    #expect(viewModel.currentStepIndex == 1)

    viewModel.replayCurrentUnit()
    for _ in 0 ..< 32 {
        if viewModel.isManualReplayPlaying == false {
            break
        }
        await Task.yield()
    }

    #expect(viewModel.isManualReplayPlaying == false)
    #expect(viewModel.currentStepIndex == 0)

    viewModel.resetSession()
}

@Test
@MainActor
func restartingManualReplayDoesNotResumeAudioRecognitionBetweenGenerations() async {
    let sleeper = PendingManualReplaySleeper()
    let audioRecognitionService = FakePracticeAudioRecognitionService()
    let playbackService = ManualReplaySequencerPlaybackService(currentSeconds: 0)
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: ManualReplayNoopPressDetectionService(),
        chordAttemptAccumulator: ManualReplayAlwaysMatchAccumulator(),
        sleeper: sleeper,
        sequencerPlaybackService: playbackService,
        audioRecognitionService: audioRecognitionService,
        manualAdvanceModeProvider: { .measure }
    )
    viewModel.setSteps(makeReplaySteps(), tempoMap: makeReplayTempoMap(), measureSpans: makeReplayMeasures())
    viewModel.startGuidingIfReady()
    await Task.yield()
    let startCallCountBeforeReplay = audioRecognitionService.startCalls.count

    viewModel.replayCurrentUnit()
    await Task.yield()
    viewModel.replayCurrentUnit()
    await Task.yield()

    #expect(viewModel.isManualReplayPlaying)
    #expect(audioRecognitionService.startCalls.count == startCallCountBeforeReplay)

    viewModel.resetSession()
}

private struct ImmediateManualReplaySleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        await Task.yield()
    }
}

private func makeReplaySteps() -> [PracticeStep] {
    [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
}

private func makeReplayMeasures() -> [MusicXMLMeasureSpan] {
    [MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 960)]
}

private func makeReplayTempoMap() -> MusicXMLTempoMap {
    MusicXMLTempoMap(tempoEvents: [MusicXMLTempoEvent(
        tick: 0,
        quarterBPM: 120,
        scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    )])
}

private func makeReplayCalibration() -> PianoCalibration {
    PianoCalibration(a0: SIMD3<Float>(0, 0, 0), c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
}

private func makeReplayKeyboardGeometry() -> PianoKeyboardGeometry {
    PianoKeyboardGeometry(
        frame: KeyboardFrame(a0World: SIMD3<Float>(0, 0, 0), c8World: SIMD3<Float>(1, 0, 0), planeHeight: 0)!,
        keys: []
    )
}

private struct PendingManualReplaySleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

private final class ManualReplaySequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let currentSecondsValue: TimeInterval
    private(set) var warmUpCount = 0
    private(set) var stopCount = 0
    private(set) var loadedSequences: [PracticeSequencerSequence] = []
    private(set) var playStarts: [TimeInterval] = []

    init(currentSeconds: TimeInterval) {
        currentSecondsValue = currentSeconds
    }

    func warmUp() throws {
        warmUpCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func load(sequence: PracticeSequencerSequence) throws {
        loadedSequences.append(sequence)
    }

    func play(fromSeconds start: TimeInterval) throws {
        playStarts.append(start)
    }

    func currentSeconds() -> TimeInterval {
        currentSecondsValue
    }

    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private struct ManualReplayNoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private struct ManualReplayConstantPressDetectionService: PressDetectionServiceProtocol {
    let pressedNotes: Set<Int>
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        pressedNotes
    }
}

private final class ManualReplayAlwaysMatchAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], tolerance _: Int, at _: Date) -> Bool {
        true
    }

    func reset() {}
}
