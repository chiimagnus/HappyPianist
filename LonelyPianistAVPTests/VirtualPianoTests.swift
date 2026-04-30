import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@MainActor
@Test
func virtualPianoToggleOffStopsAllLiveNotes() {
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.stopVirtualPianoInput()

    #expect(playbackService.stopAllLiveNotesCount == 1)
    #expect(viewModel.pressedNotes.isEmpty)
}

@MainActor
@Test
func autoplayEnabledStopsLiveNotes() {
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: .init(partID: "P1", staff: nil, voice: nil))]
    )
    viewModel.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        tempoMap: tempoMap
    )

    viewModel.setAutoplayEnabled(true)

    #expect(playbackService.stopAllLiveNotesCount >= 1)
}

@MainActor
@Test
func virtualPianoNoteOnTriggersLiveStart() {
    let playbackService = LiveNoteCapturingPlaybackService()
    let chordAccumulator = RecordingChordAttemptAccumulator()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: chordAccumulator,
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    let tempoMap = MusicXMLTempoMap(
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: .init(partID: "P1", staff: nil, voice: nil))]
    )
    viewModel.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        tempoMap: tempoMap
    )
    viewModel.startGuidingIfReady()

    let geometry = makeTestKeyboardGeometry()
    viewModel.applyVirtualKeyboardGeometry(geometry)

    let c4Key = geometry.key(for: 60)!
    let fingerTips: [String: SIMD3<Float>] = [
        "right_indexFinger_tip": SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z),
    ]
    let detected = viewModel.handleFingerTipPositions(fingerTips, isVirtualPiano: true)

    #expect(detected.contains(60))
    #expect(playbackService.startedLiveNotes.contains(60))
    #expect(chordAccumulator.registerCallCount >= 1)
}

@MainActor
@Test
func physicalPianoPathUnaffectedByVirtualPiano() {
    let pressDetection = NoopPressDetectionService()
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: pressDetection,
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    let geometry = makeTestKeyboardGeometry()
    let calibration = PianoCalibration(
        a0: .init(x: 0, y: 0, z: 0),
        c8: .init(x: 1.2, y: 0, z: 0),
        planeHeight: 0,
        whiteKeyWidth: 0.0235,
        frontEdgeToKeyCenterLocalZ: 0.07
    )
    viewModel.applyKeyboardGeometry(geometry, calibration: calibration)

    let fingerTips: [String: SIMD3<Float>] = [
        "right_indexFinger_tip": SIMD3<Float>(0.5, 0, 0),
    ]
    let detected = viewModel.handleFingerTipPositions(fingerTips, isVirtualPiano: false)

    #expect(playbackService.startedLiveNotes.isEmpty)
    #expect(playbackService.stopAllLiveNotesCount == 0)
    _ = detected
}

// MARK: - Helpers

private func makeTestKeyboardGeometry() -> PianoKeyboardGeometry {
    let xAxis = SIMD3<Float>(1, 0, 0)
    let yAxis = SIMD3<Float>(0, 1, 0)
    let zAxis = SIMD3<Float>(0, 0, 1)
    let origin = SIMD3<Float>(0, 0, 0)
    let transform = simd_float4x4(columns: (
        SIMD4<Float>(xAxis, 0),
        SIMD4<Float>(yAxis, 0),
        SIMD4<Float>(zAxis, 0),
        SIMD4<Float>(origin, 1)
    ))
    let frame = KeyboardFrame(worldFromKeyboard: transform)
    let service = VirtualPianoKeyGeometryService()
    return service.generateKeyboardGeometry(from: frame)!
}

private final class LiveNoteCapturingPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var stopAllLiveNotesCount = 0
    private(set) var startedLiveNotes: Set<Int> = []
    private(set) var stoppedLiveNotes: Set<Int> = []

    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}

    func startLiveNotes(midiNotes: Set<Int>) throws {
        startedLiveNotes.formUnion(midiNotes)
    }

    func stopLiveNotes(midiNotes: Set<Int>) {
        stoppedLiveNotes.formUnion(midiNotes)
    }

    func stopAllLiveNotes() {
        stopAllLiveNotesCount += 1
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
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], tolerance _: Int, at _: Date) -> Bool {
        false
    }

    func reset() {}
}

private final class RecordingChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    private(set) var registerCallCount = 0
    private(set) var lastPressedNotes: Set<Int> = []
    private(set) var lastExpectedNotes: [Int] = []
    var shouldReturnMatched = false

    func register(pressedNotes: Set<Int>, expectedNotes: [Int], tolerance: Int, at timestamp: Date) -> Bool {
        registerCallCount += 1
        lastPressedNotes = pressedNotes
        lastExpectedNotes = expectedNotes
        return shouldReturnMatched
    }

    func reset() {}
}
