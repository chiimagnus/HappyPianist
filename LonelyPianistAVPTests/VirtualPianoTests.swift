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
        "right-indexFingerTip": SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z),
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
        "right-indexFingerTip": SIMD3<Float>(0.5, 0, 0),
    ]
    let detected = viewModel.handleFingerTipPositions(fingerTips, isVirtualPiano: false)

    #expect(playbackService.startedLiveNotes.isEmpty)
    #expect(playbackService.stopAllLiveNotesCount == 0)
    _ = detected
}

// MARK: - KeyContactDetectionService Tests

@MainActor
@Test
func keyContactDetectionStartedEndedHysteresis() {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()
    let c4Key = geometry.key(for: 60)!

    let atSurface: [String: SIMD3<Float>] = [
        "right-indexFingerTip": SIMD3<Float>(c4Key.hitCenterLocal.x, c4Key.surfaceLocalY, c4Key.hitCenterLocal.z),
    ]
    let result1 = service.detect(fingerTips: atSurface, keyboardGeometry: geometry)
    #expect(result1.started.contains(60))
    #expect(result1.down.contains(60))

    let betweenThresholds: [String: SIMD3<Float>] = [
        "right-indexFingerTip": SIMD3<Float>(
            c4Key.hitCenterLocal.x,
            c4Key.surfaceLocalY + (KeyContactDetectionService.pressThresholdMeters + KeyContactDetectionService.releaseThresholdMeters) / 2,
            c4Key.hitCenterLocal.z
        ),
    ]
    let result2 = service.detect(fingerTips: betweenThresholds, keyboardGeometry: geometry)
    #expect(result2.down.contains(60), "Between press/release threshold: should stay down (hysteresis)")
    #expect(result2.started.isEmpty)
    #expect(result2.ended.isEmpty)

    let aboveRelease: [String: SIMD3<Float>] = [
        "right-indexFingerTip": SIMD3<Float>(
            c4Key.hitCenterLocal.x,
            c4Key.surfaceLocalY + KeyContactDetectionService.releaseThresholdMeters + 0.001,
            c4Key.hitCenterLocal.z
        ),
    ]
    let result3 = service.detect(fingerTips: aboveRelease, keyboardGeometry: geometry)
    #expect(result3.ended.contains(60))
    #expect(result3.down.isEmpty)
}

@MainActor
@Test
func keyContactDetectionBlackKeyPriority() {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()

    let blackKey = geometry.keys.first { $0.kind == .black }!
    let blackMin = blackKey.hitCenterLocal - blackKey.hitSizeLocal / 2
    let blackMax = blackKey.hitCenterLocal + blackKey.hitSizeLocal / 2
    let whiteKeys = geometry.keys.filter { $0.kind == .white }
    let overlappingWhite = whiteKeys.first { whiteKey in
        let whiteMin = whiteKey.hitCenterLocal - whiteKey.hitSizeLocal / 2
        let whiteMax = whiteKey.hitCenterLocal + whiteKey.hitSizeLocal / 2
        return max(blackMin.x, whiteMin.x) < min(blackMax.x, whiteMax.x)
            && max(blackMin.z, whiteMin.z) < min(blackMax.z, whiteMax.z)
    }
    #expect(overlappingWhite != nil, "Test setup: expected at least one white key overlap with a black key footprint")

    let overlapPointX: Float = {
        guard let overlappingWhite else { return blackKey.hitCenterLocal.x }
        let whiteMin = overlappingWhite.hitCenterLocal - overlappingWhite.hitSizeLocal / 2
        let whiteMax = overlappingWhite.hitCenterLocal + overlappingWhite.hitSizeLocal / 2
        return (max(blackMin.x, whiteMin.x) + min(blackMax.x, whiteMax.x)) / 2
    }()

    let fingerTips: [String: SIMD3<Float>] = [
        "right-indexFingerTip": SIMD3<Float>(overlapPointX, -0.001, blackKey.hitCenterLocal.z),
    ]
    let result = service.detect(fingerTips: fingerTips, keyboardGeometry: geometry)
    #expect(result.down == [blackKey.midiNote])
}

@MainActor
@Test
func keyContactDetectionNoFingerNoDown() {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()

    let result = service.detect(fingerTips: [:], keyboardGeometry: geometry)
    #expect(result.down.isEmpty)
    #expect(result.started.isEmpty)
    #expect(result.ended.isEmpty)
}

// MARK: - VirtualPianoPlacementViewModel Tests

@Test
@MainActor
func placementStateTransitions() {
    let vm = VirtualPianoPlacementViewModel()
    #expect(vm.state == .disabled)
    #expect(vm.isPlaced == false)
    #expect(vm.worldFromKeyboard == nil)

    vm.startPlacing()
    if case let .placing(reticlePoint) = vm.state {
        #expect(reticlePoint == nil)
    } else {
        Issue.record("Expected .placing state")
    }

    vm.update(fingerTips: [
        "right-indexFingerTip": SIMD3<Float>(0.5, 0, 0),
        "right-thumbTip": SIMD3<Float>(0.5, 0, 0),
    ])
    #expect(vm.isPlaced)
    #expect(vm.worldFromKeyboard != nil)
}

@Test
@MainActor
func placementResetGoesToDisabled() {
    let vm = VirtualPianoPlacementViewModel()
    vm.startPlacing()
    vm.update(fingerTips: [
        "right-indexFingerTip": SIMD3<Float>(0, 0, 0),
        "right-thumbTip": SIMD3<Float>(0, 0, 0),
    ])
    #expect(vm.isPlaced)

    vm.reset()
    #expect(vm.state == .disabled)
    #expect(vm.isPlaced == false)
}

@Test
@MainActor
func placementConfirmSetsOriginAtKeyboardLeftEnd() {
    let vm = VirtualPianoPlacementViewModel()
    vm.startPlacing()

    let reticlePoint = SIMD3<Float>(1.0, 0, 0)
    vm.update(fingerTips: [
        "right-indexFingerTip": reticlePoint,
        "right-thumbTip": reticlePoint,
    ])

    guard let transform = vm.worldFromKeyboard else {
        Issue.record("Expected placement to succeed")
        return
    }
    let origin = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    let halfLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters / 2
    #expect(abs(origin.x - (reticlePoint.x - halfLength)) < 0.001)
}

@MainActor
@Test
func virtualPianoDoesNotTriggerLiveNotesDuringAutoplay() {
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

    let geometry = makeTestKeyboardGeometry()
    viewModel.applyVirtualKeyboardGeometry(geometry)
    viewModel.setAutoplayEnabled(true)

    let c4Key = geometry.key(for: 60)!
    _ = viewModel.handleFingerTipPositions(
        [
            "right-indexFingerTip": SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z),
        ],
        isVirtualPiano: true
    )

    #expect(playbackService.startedLiveNotes.isEmpty)
}

@MainActor
@Test
func arGuideViewModelToggleOffClearsVirtualKeyboardAndStopsLiveNotes() {
    let playbackService = LiveNoteCapturingPlaybackService()
    let session = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )
    let appState = AppState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSessionViewModel: session)

    viewModel.setPracticeVirtualPianoEnabled(true)
    #expect(viewModel.virtualPianoPlacement.isPlaced)
    #expect(session.keyboardGeometry != nil)

    let geometry = session.keyboardGeometry!
    let c4Key = geometry.key(for: 60)!
    let keyLocalPoint = SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z)
    let keyWorldPoint = transformPoint(geometry.frame.worldFromKeyboard, keyLocalPoint)
    _ = session.handleFingerTipPositions(
        [
            "right-indexFingerTip": keyWorldPoint,
        ],
        isVirtualPiano: true
    )
    #expect(playbackService.startedLiveNotes.contains(60))

    viewModel.setPracticeVirtualPianoEnabled(false)
    #expect(playbackService.stopAllLiveNotesCount >= 1)
    #expect(session.keyboardGeometry == nil)
}

private func transformPoint(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
    let v4 = simd_mul(matrix, SIMD4<Float>(point, 1))
    return SIMD3<Float>(v4.x, v4.y, v4.z)
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
