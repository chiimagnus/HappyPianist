import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
@MainActor
func appStateAppliesKeyboardGeometryWhenAvailable() throws {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.5, 0.0),
        c8: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )
    let frame = try #require(calibration.keyboardFrame)
    let geometry = PianoKeyboardGeometry(frame: frame, keys: [])

    let service = CapturingKeyGeometryService(result: geometry)
    let practiceSessionViewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    let appState = AppState(keyGeometryService: service)
    let practiceSetupState = PracticeSetupState()
    let guideViewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: EmptyPianoModeRegistry(),
        makePracticeSessionViewModel: SinglePracticeSessionViewModelProvider(session: practiceSessionViewModel).callAsFunction
    )
    _ = guideViewModel

    appState.calibration = calibration

    #expect(service.callCount == 1)
    #expect(practiceSessionViewModel.keyboardGeometry != nil)
}

@Test
@MainActor
func appStateDoesNotApplyKeyboardGeometryWhenGenerationFails() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.5, 0.0),
        c8: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let service = CapturingKeyGeometryService(result: nil)
    let practiceSessionViewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )

    let appState = AppState(keyGeometryService: service)
    let practiceSetupState = PracticeSetupState()
    let guideViewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: EmptyPianoModeRegistry(),
        makePracticeSessionViewModel: SinglePracticeSessionViewModelProvider(session: practiceSessionViewModel).callAsFunction
    )
    _ = guideViewModel

    appState.calibration = calibration

    #expect(service.callCount == 1)
    #expect(practiceSessionViewModel.keyboardGeometry == nil)
}

private final class CapturingKeyGeometryService: PianoKeyGeometryServiceProtocol {
    private let result: PianoKeyboardGeometry?
    private(set) var callCount = 0

    init(result: PianoKeyboardGeometry?) {
        self.result = result
    }

    func generateKeyboardGeometry(from _: PianoCalibration) -> PianoKeyboardGeometry? {
        callCount += 1
        return result
    }
}

@MainActor
private final class SinglePracticeSessionViewModelProvider: @unchecked Sendable {
    private let session: PracticeSessionViewModel

    init(session: PracticeSessionViewModel) {
        self.session = session
    }

    func callAsFunction(_: String?) -> PracticeSessionViewModel {
        session
    }
}

private struct EmptyPianoModeRegistry: PianoModeRegistryProtocol {
    let modes: [any PianoModeProtocol] = []

    func mode(for _: String?) -> (any PianoModeProtocol)? {
        nil
    }
}

@MainActor
private final class NoopSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}
