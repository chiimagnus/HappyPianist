import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@MainActor
@Test
func virtualPianoToggleOffStopsAllLiveNotes() async {
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.stopVirtualPianoInput()
    await Task.yield()

    #expect(playbackService.stopAllLiveNotesCount == 1)
    #expect(viewModel.pressedNotes.isEmpty)
}

@MainActor
@Test
func autoplayEnabledStopsLiveNotes() async {
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)]
    )

    viewModel.setAutoplayEnabled(true)
    await Task.yield()

    #expect(playbackService.stopAllLiveNotesCount >= 1)
}

@MainActor
@Test
func virtualPianoNoteOnTriggersLiveStart() async throws {
    let playbackService = LiveNoteCapturingPlaybackService()
    let chordAccumulator = RecordingChordAttemptAccumulator()
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: chordAccumulator,
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)]
    )
    viewModel.startGuidingIfReady()

    let geometry = makeTestKeyboardGeometry()
    viewModel.applyVirtualKeyboardGeometry(geometry)

    let c4Key = try #require(geometry.key(for: 60))
    let aboveSurface = FingerTipsSnapshot(
        right: HandTips(index: SIMD3<Float>(c4Key.hitCenterLocal.x, 0.02, c4Key.hitCenterLocal.z))
    )
    _ = viewModel.handleFingerTipPositions(
        aboveSurface,
        isVirtualPiano: true,
        at: .init(seconds: 1)
    )
    let fingerTips = FingerTipsSnapshot(
        right: HandTips(index: SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z))
    )
    let detected = viewModel.handleFingerTipPositions(
        fingerTips,
        isVirtualPiano: true,
        at: .init(seconds: 1.05)
    )
    await Task.yield()

    #expect(detected.contains(60))
    #expect(playbackService.startedLiveNotes.contains(60))
    #expect(chordAccumulator.registerCallCount >= 1)
}

@MainActor
@Test
func physicalPianoPathUnaffectedByVirtualPiano() {
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
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

    let fingerTips = FingerTipsSnapshot(
        right: HandTips(index: SIMD3<Float>(0.5, 0, 0))
    )
    let detected = viewModel.handleFingerTipPositions(fingerTips, isVirtualPiano: false)

    #expect(playbackService.startedLiveNotes.isEmpty)
    #expect(playbackService.stopAllLiveNotesCount == 0)
    _ = detected
}

// MARK: - KeyContactDetectionService Tests

@MainActor
@Test
func keyContactDetectionStartedEndedHysteresis() throws {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()
    let c4Key = try #require(geometry.key(for: 60))

    let atSurface = FingerTipsSnapshot(
        right: HandTips(
            index: SIMD3<Float>(c4Key.hitCenterLocal.x, c4Key.surfaceLocalY, c4Key.hitCenterLocal.z)
        )
    )
    _ = service.detect(
        fingerTips: FingerTipsSnapshot(
            right: HandTips(
                index: SIMD3<Float>(c4Key.hitCenterLocal.x, c4Key.surfaceLocalY + 0.02, c4Key.hitCenterLocal.z)
            )
        ),
        keyboardGeometry: geometry,
        at: .init(seconds: 0.95)
    )
    let result1 = service.detect(fingerTips: atSurface, keyboardGeometry: geometry, at: .init(seconds: 1))
    let started = try #require(result1.first)
    #expect(result1.startedMIDINotes == [60])
    #expect(result1.activeMIDINotes == [60])
    #expect(started.phase == .started)
    #expect(started.hand == .right)
    #expect(started.finger == .index)
    #expect(started.timestamp == .init(seconds: 1))
    #expect(started.confidence == 1)
    #expect(started.worldPosition == atSurface.right.index)
    #expect(started.planeDistanceMeters == 0)
    #expect(abs((started.normalVelocityMetersPerSecond ?? 0) + 0.4) < 0.0001)
    #expect(started.calibrationID == service.calibration.id)
    #expect(started.resolvedVelocity != nil)

    let betweenThresholds = FingerTipsSnapshot(
        right: HandTips(
            index: SIMD3<Float>(
                c4Key.hitCenterLocal.x,
                c4Key.surfaceLocalY
                    + (service.calibration.planeOffsetMeters
                        + service.calibration.releaseThresholdMeters) / 2,
                c4Key.hitCenterLocal.z
            )
        )
    )
    let result2 = service.detect(
        fingerTips: betweenThresholds,
        keyboardGeometry: geometry,
        at: .init(seconds: 1.05)
    )
    let held = try #require(result2.first)
    #expect(result2.activeMIDINotes == [60], "Between press/release threshold: should stay down (hysteresis)")
    #expect(result2.startedMIDINotes.isEmpty)
    #expect(result2.endedMIDINotes.isEmpty)
    #expect(held.phase == .held)
    #expect(held.id == started.id)

    let aboveRelease = FingerTipsSnapshot(
        right: HandTips(
            index: SIMD3<Float>(
                c4Key.hitCenterLocal.x,
                c4Key.surfaceLocalY + service.calibration.releaseThresholdMeters + 0.001,
                c4Key.hitCenterLocal.z
            )
        )
    )
    let result3 = service.detect(fingerTips: aboveRelease, keyboardGeometry: geometry, at: .init(seconds: 1.10))
    let ended = try #require(result3.first)
    #expect(result3.endedMIDINotes == [60])
    #expect(result3.activeMIDINotes.isEmpty)
    #expect(ended.phase == .ended)
    #expect(ended.id == started.id)
    #expect(ended.timestamp == .init(seconds: 1.10))
}

@MainActor
@Test
func keyContactDetectionTracksSameKeyPerFingerAndDebouncesRetrigger() throws {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()
    let key = try #require(geometry.key(for: 60))
    let position = SIMD3<Float>(key.hitCenterLocal.x, key.surfaceLocalY, key.hitCenterLocal.z)

    let first = service.detect(
        fingerTips: FingerTipsSnapshot(left: HandTips(index: position), right: HandTips(index: position)),
        keyboardGeometry: geometry,
        at: .init(seconds: 1)
    )
    #expect(first.count == 2)
    #expect(first.allSatisfy { $0.phase == .started })
    #expect(Set(first.map(\.id)).count == 2)
    let leftID = try #require(first.first { $0.hand == .left }?.id)
    let rightID = try #require(first.first { $0.hand == .right }?.id)

    let second = service.detect(
        fingerTips: FingerTipsSnapshot(left: HandTips(index: position)),
        keyboardGeometry: geometry,
        at: .init(seconds: 1.05)
    )
    #expect(second.activeMIDINotes == [60])
    #expect(second.first { $0.phase == .held }?.id == leftID)
    #expect(second.first { $0.phase == .ended }?.id == rightID)

    let released = service.detect(
        fingerTips: .empty,
        keyboardGeometry: geometry,
        at: .init(seconds: 1.10)
    )
    #expect(released.first?.phase == .ended)
    #expect(released.first?.id == leftID)

    let suppressedRetrigger = service.detect(
        fingerTips: FingerTipsSnapshot(left: HandTips(index: position)),
        keyboardGeometry: geometry,
        at: .init(seconds: 1.11)
    )
    #expect(suppressedRetrigger.isEmpty)

    let retriggered = service.detect(
        fingerTips: FingerTipsSnapshot(left: HandTips(index: position)),
        keyboardGeometry: geometry,
        at: .init(seconds: 1.14)
    )
    #expect(retriggered.first?.phase == .started)
    #expect(retriggered.first?.id != leftID)

    let replacementGeometry = PianoKeyboardGeometry(frame: geometry.frame, keys: geometry.keys)
    let placementReset = service.detect(
        fingerTips: FingerTipsSnapshot(left: HandTips(index: position)),
        keyboardGeometry: replacementGeometry,
        at: .init(seconds: 1.20)
    )
    #expect(placementReset.count == 1)
    #expect(placementReset.first?.phase == .ended)
    #expect(placementReset.first?.calibrationID == service.calibration.id)
}

@MainActor
@Test
func keyContactDetectionBlackKeyPriority() throws {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()

    let blackKey = try #require(geometry.keys.first { $0.kind == .black })
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

    let fingerTips = FingerTipsSnapshot(
        right: HandTips(index: SIMD3<Float>(overlapPointX, -0.001, blackKey.hitCenterLocal.z))
    )
    let result = service.detect(fingerTips: fingerTips, keyboardGeometry: geometry, at: .init(seconds: 1))
    #expect(result.activeMIDINotes == [blackKey.midiNote])
}

@MainActor
@Test
func keyContactDetectionNoFingerNoDown() {
    let service = KeyContactDetectionService()
    let geometry = makeTestKeyboardGeometry()

    let result = service.detect(fingerTips: .empty, keyboardGeometry: geometry, at: .init(seconds: 1))
    #expect(result.isEmpty)
}

@MainActor
@Test
func virtualPianoDoesNotTriggerLiveNotesDuringAutoplay() throws {
    let playbackService = LiveNoteCapturingPlaybackService()
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )

    viewModel.installTestPerformanceNotes(
        [TestScorePerformanceNote(midiNote: 60, onTick: 0)]
    )

    let geometry = makeTestKeyboardGeometry()
    viewModel.applyVirtualKeyboardGeometry(geometry)
    viewModel.setAutoplayEnabled(true)

    let c4Key = try #require(geometry.key(for: 60))
    _ = viewModel.handleFingerTipPositions(
        FingerTipsSnapshot(
            right: HandTips(index: SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z))
        ),
        isVirtualPiano: true
    )

    #expect(playbackService.startedLiveNotes.isEmpty)
}

@MainActor
@Test
func arGuideViewModelToggleOffClearsVirtualKeyboardAndStopsLiveNotes() async throws {
    let playbackService = LiveNoteCapturingPlaybackService()
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService
    )
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: SinglePracticeSessionViewModelProvider(session: session).callAsFunction
    )

    let geometry = makeTestKeyboardGeometry()
    session.applyVirtualKeyboardGeometry(geometry)

    let c4Key = try #require(geometry.key(for: 60))
    let aboveKeyWorldPoint = transformPoint(
        geometry.frame.worldFromKeyboard,
        SIMD3<Float>(c4Key.hitCenterLocal.x, 0.02, c4Key.hitCenterLocal.z)
    )
    _ = session.handleFingerTipPositions(
        FingerTipsSnapshot(right: HandTips(index: aboveKeyWorldPoint)),
        isVirtualPiano: true,
        at: .init(seconds: 1)
    )
    let keyLocalPoint = SIMD3<Float>(c4Key.hitCenterLocal.x, -0.001, c4Key.hitCenterLocal.z)
    let keyWorldPoint = transformPoint(geometry.frame.worldFromKeyboard, keyLocalPoint)
    _ = session.handleFingerTipPositions(
        FingerTipsSnapshot(right: HandTips(index: keyWorldPoint)),
        isVirtualPiano: true,
        at: .init(seconds: 1.05)
    )
    await Task.yield()
    #expect(playbackService.startedLiveNotes.contains(60))

    viewModel.setPracticeVirtualPianoEnabled(false)
    await Task.yield()
    #expect(playbackService.stopAllLiveNotesCount >= 1)
    #expect(session.keyboardGeometry == nil)
}

@MainActor
@Test
func hidingVirtualPianoPreservesPlacedKeyboardForLaterPractice() async {
    let session = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: LiveNoteCapturingPlaybackService()
    )
    let viewModel = ARGuideViewModel(
        appState: AppState(),
        practiceSetupState: PracticeSetupState(),
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: SinglePracticeSessionViewModelProvider(session: session).callAsFunction
    )

    viewModel.setPracticeVirtualPianoEnabled(true)

    await viewModel.enterPracticeStep(
        openImmersiveSpace: { _ in .opened },
        dismissImmersiveSpace: {}
    )
    session.applyVirtualKeyboardGeometry(makeTestKeyboardGeometry())
    #expect(viewModel.shouldShowVirtualPiano)

    viewModel.hideVirtualPiano()

    #expect(viewModel.shouldShowVirtualPiano == false)
    #expect(session.keyboardGeometry != nil)
}

@MainActor
private final class SinglePracticeSessionViewModelProvider: @unchecked Sendable {
    private let session: PracticeSessionViewModel

    init(session: PracticeSessionViewModel) {
        self.session = session
    }

    @MainActor
    func callAsFunction(_: String?) -> PracticeSessionViewModel {
        session
    }
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
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}

    func execute(commands: [PracticePlaybackCommand]) throws {
        for command in commands {
            switch command.kind {
            case let .noteOn(midi, _):
                startedLiveNotes.insert(midi)
            case let .noteOff(midi):
                stoppedLiveNotes.insert(midi)
            case .controlChange, .programChange, .pitchBend, .polyPressure, .channelPressure:
                break
            }
        }
    }

    func stopAllLiveNotes() {
        stopAllLiveNotesCount += 1
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], at _: PerformanceMonotonicInstant) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

private final class RecordingChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    private(set) var registerCallCount = 0
    private(set) var lastPressedNotes: Set<Int> = []
    private(set) var lastExpectedNotes: [Int] = []
    var shouldReturnMatched = false

    func register(pressedNotes: Set<Int>, expectedNotes: [Int], at _: PerformanceMonotonicInstant) -> StepAttemptMatchResult {
        registerCallCount += 1
        lastPressedNotes = pressedNotes
        lastExpectedNotes = expectedNotes
        return testAttemptOutcome(
            matched: shouldReturnMatched,
            pressedNotes: pressedNotes,
            expectedNotes: expectedNotes
        )
    }

    func reset() {}
}
