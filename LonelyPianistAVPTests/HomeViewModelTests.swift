import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
@MainActor
func canEnterPracticeIsTrueWhenMissingCalibration() {
    let appModel = makeAppModel(
        calibration: nil,
        hasImportedSteps: true,
        hasStoredCalibration: false,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.canEnterPractice)
    #expect(viewModel.practiceEntryHelpText?.contains("Step 1 校准") == true)
}

@Test
@MainActor
func canEnterPracticeIsTrueWhenMissingImportedSteps() {
    let appModel = makeAppModel(
        calibration: sampleCalibration(),
        hasImportedSteps: false,
        hasStoredCalibration: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.canEnterPractice)
    #expect(viewModel.practiceEntryHelpText?.contains("导入 MusicXML") == true)
}

@Test
@MainActor
func canEnterPracticeIsTrueWhenCalibrationAndImportedStepsExist() {
    let appModel = makeAppModel(
        calibration: sampleCalibration(),
        hasImportedSteps: true,
        hasStoredCalibration: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.canEnterPractice)
    #expect(viewModel.practiceEntryHelpText == nil)
}

@Test
@MainActor
func practiceEntryShowsLocatingHintWhenStoredCalibrationExistsButRuntimeCalibrationMissing() {
    let appModel = makeAppModel(
        calibration: nil,
        hasImportedSteps: true,
        hasStoredCalibration: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appModel: appModel)

    #expect(viewModel.practiceEntryHelpText?.contains("定位钢琴") == true)
}

@Test
@MainActor
func canImportScoreDependsOnImmersiveState() {
    let closedModel = HomeViewModel(
        appModel: makeAppModel(
            calibration: nil,
            hasImportedSteps: false,
            hasStoredCalibration: false,
            immersiveState: .closed
        )
    )
    #expect(closedModel.canImportScore)

    let openModel = HomeViewModel(
        appModel: makeAppModel(
            calibration: nil,
            hasImportedSteps: false,
            hasStoredCalibration: false,
            immersiveState: .open
        )
    )
    #expect(openModel.canImportScore == false)

    let transitionModel = HomeViewModel(
        appModel: makeAppModel(
            calibration: nil,
            hasImportedSteps: false,
            hasStoredCalibration: false,
            immersiveState: .inTransition
        )
    )
    #expect(transitionModel.canImportScore == false)
}

@MainActor
private func makeAppModel(
    calibration: PianoCalibration?,
    hasImportedSteps: Bool,
    hasStoredCalibration: Bool,
    immersiveState: AppModel.ImmersiveSpaceState
) -> AppModel {
    let appModel = AppModel()
    appModel.immersiveSpaceState = immersiveState
    appModel.calibration = calibration

    if hasStoredCalibration {
        appModel.storedCalibration = StoredWorldAnchorCalibration(
            a0AnchorID: UUID(),
            c8AnchorID: UUID(),
            whiteKeyWidth: 0.0235
        )
    }

    if hasImportedSteps {
        appModel.setImportedSteps(
            [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
            file: nil,
            tempoMap: MusicXMLTempoMap(tempoEvents: [])
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
