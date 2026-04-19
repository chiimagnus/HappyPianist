import Testing
import simd
@testable import LonelyPianistAVP

@Test
@MainActor
func canEnterPracticeIsFalseWhenMissingCalibration() {
    let appModel = makeAppModel(
        calibration: nil,
        hasImportedSteps: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.canEnterPractice == false)
}

@Test
@MainActor
func canEnterPracticeIsFalseWhenMissingImportedSteps() {
    let appModel = makeAppModel(
        calibration: sampleCalibration(),
        hasImportedSteps: false,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.canEnterPractice == false)
}

@Test
@MainActor
func canEnterPracticeIsTrueWhenCalibrationAndImportedStepsExist() {
    let appModel = makeAppModel(
        calibration: sampleCalibration(),
        hasImportedSteps: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.canEnterPractice)
}

@Test
@MainActor
func canImportScoreDependsOnImmersiveState() {
    let closedModel = HomeViewModel(
        appModel: makeAppModel(
            calibration: nil,
            hasImportedSteps: false,
            immersiveState: .closed
        )
    )
    #expect(closedModel.canImportScore)

    let openModel = HomeViewModel(
        appModel: makeAppModel(
            calibration: nil,
            hasImportedSteps: false,
            immersiveState: .open
        )
    )
    #expect(openModel.canImportScore == false)

    let transitionModel = HomeViewModel(
        appModel: makeAppModel(
            calibration: nil,
            hasImportedSteps: false,
            immersiveState: .inTransition
        )
    )
    #expect(transitionModel.canImportScore == false)
}

@MainActor
private func makeAppModel(
    calibration: PianoCalibration?,
    hasImportedSteps: Bool,
    immersiveState: AppModel.ImmersiveSpaceState
) -> AppModel {
    let appModel = AppModel()
    appModel.immersiveSpaceState = immersiveState
    appModel.calibration = calibration

    if hasImportedSteps {
        appModel.setImportedSteps(
            [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
            file: nil
        )
    }

    return appModel
}

private func sampleCalibration() -> PianoCalibration {
    PianoCalibration(
        a0: SIMD3<Float>(-0.7, 0.8, -1.0),
        c8: SIMD3<Float>(0.7, 0.8, -1.0),
        planeHeight: 0.8
    )
}
