import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
@MainActor
func appModelAppliesKeyboardGeometryWhenAvailable() throws {
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
        pressDetectionService: PressDetectionService(),
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        noteAudioPlayer: nil
    )

    let appModel = AppModel(
        keyGeometryService: service,
        practiceSessionViewModel: practiceSessionViewModel
    )

    appModel.calibration = calibration

    #expect(service.callCount == 1)
    #expect(appModel.practiceSessionViewModel.keyboardGeometry != nil)
}

@Test
@MainActor
func appModelDoesNotApplyKeyboardGeometryWhenGenerationFails() {
    let calibration = PianoCalibration(
        a0: SIMD3<Float>(0.0, 0.5, 0.0),
        c8: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5,
        frontEdgeToKeyCenterLocalZ: -PianoKeyGeometryService.whiteKeyDepthMeters / 2
    )

    let service = CapturingKeyGeometryService(result: nil)
    let practiceSessionViewModel = PracticeSessionViewModel(
        pressDetectionService: PressDetectionService(),
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        noteAudioPlayer: nil
    )

    let appModel = AppModel(
        keyGeometryService: service,
        practiceSessionViewModel: practiceSessionViewModel
    )

    appModel.calibration = calibration

    #expect(service.callCount == 1)
    #expect(appModel.practiceSessionViewModel.keyboardGeometry == nil)
}

private final class CapturingKeyGeometryService: PianoKeyGeometryServiceProtocol {
    private let result: PianoKeyboardGeometry?
    private(set) var callCount = 0

    init(result: PianoKeyboardGeometry?) {
        self.result = result
    }

    func generateKeyboardGeometry(from calibration: PianoCalibration) -> PianoKeyboardGeometry? {
        callCount += 1
        return result
    }
}
