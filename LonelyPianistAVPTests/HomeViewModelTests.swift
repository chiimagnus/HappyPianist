import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
@MainActor
func canEnterPracticeIsTrueWhenMissingCalibration() {
    let appState = makeAppState(
        calibration: nil,
        hasImportedSteps: true,
        hasStoredCalibration: false,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appState: appState)

    #expect(viewModel.canEnterPractice)
    #expect(viewModel.practiceEntryHelpText?.contains("Step 1 校准") == true)
}

@Test
@MainActor
func canEnterPracticeIsTrueWhenMissingImportedSteps() {
    let appState = makeAppState(
        calibration: sampleCalibration(),
        hasImportedSteps: false,
        hasStoredCalibration: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appState: appState)

    #expect(viewModel.canEnterPractice)
    #expect(viewModel.practiceEntryHelpText?.contains("导入 MusicXML") == true)
}

@Test
@MainActor
func canEnterPracticeIsTrueWhenCalibrationAndImportedStepsExist() {
    let appState = makeAppState(
        calibration: sampleCalibration(),
        hasImportedSteps: true,
        hasStoredCalibration: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appState: appState)

    #expect(viewModel.canEnterPractice)
    #expect(viewModel.practiceEntryHelpText == nil)
}

@Test
@MainActor
func practiceEntryShowsLocatingHintWhenStoredCalibrationExistsButRuntimeCalibrationMissing() {
    let appState = makeAppState(
        calibration: nil,
        hasImportedSteps: true,
        hasStoredCalibration: true,
        immersiveState: .closed
    )
    let viewModel = HomeViewModel(appState: appState)

    #expect(viewModel.practiceEntryHelpText?.contains("定位钢琴") == true)
}

@Test
@MainActor
func canImportScoreDependsOnImmersiveState() {
    let closedModel = HomeViewModel(
        appState: makeAppState(
            calibration: nil,
            hasImportedSteps: false,
            hasStoredCalibration: false,
            immersiveState: .closed
        )
    )
    #expect(closedModel.canImportScore)

    let openModel = HomeViewModel(
        appState: makeAppState(
            calibration: nil,
            hasImportedSteps: false,
            hasStoredCalibration: false,
            immersiveState: .open
        )
    )
    #expect(openModel.canImportScore == false)

    let transitionModel = HomeViewModel(
        appState: makeAppState(
            calibration: nil,
            hasImportedSteps: false,
            hasStoredCalibration: false,
            immersiveState: .inTransition
        )
    )
    #expect(transitionModel.canImportScore == false)
}

@MainActor
private func makeAppState(
    calibration: PianoCalibration?,
    hasImportedSteps: Bool,
    hasStoredCalibration: Bool,
    immersiveState: AppState.ImmersiveSpaceState
) -> AppState {
    let appState = AppState()
    appState.immersiveSpaceState = immersiveState
    appState.calibration = calibration

    if hasStoredCalibration {
        appState.storedCalibration = StoredWorldAnchorCalibration(
            a0AnchorID: UUID(),
            c8AnchorID: UUID(),
            whiteKeyWidth: 0.0235
        )
    }

    if hasImportedSteps {
        appState.setImportedSteps(from: PreparedPractice(
            steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
            file: ImportedMusicXMLFile(fileName: "Test", storedURL: URL(fileURLWithPath: "/dev/null"), importedAt: Date()),
            tempoMap: MusicXMLTempoMap(tempoEvents: []),
            pedalTimeline: nil,
            fermataTimeline: nil,
            attributeTimeline: nil,
            slurTimeline: nil,
            noteSpans: [],
            highlightGuides: [],
            measureSpans: [],
            unsupportedNoteCount: 0
        ))
    }

    return appState
}

private func sampleCalibration() -> PianoCalibration {
    PianoCalibration(
        a0: SIMD3<Float>(-0.7, 0.8, -1.0),
        c8: SIMD3<Float>(0.7, 0.8, -1.0),
        planeHeight: 0.8
    )
}
