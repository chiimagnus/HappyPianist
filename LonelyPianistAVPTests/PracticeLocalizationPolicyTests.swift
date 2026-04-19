import Foundation
import Testing
@testable import LonelyPianistAVP

@Test
@MainActor
func practiceEntryBlockingReasonIsMissingImportedStepsFirst() {
    let appModel = AppModel()
    appModel.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )

    let viewModel = ARGuideViewModel(appModel: appModel)
    #expect(viewModel.practiceEntryBlockingReason() == .missingImportedSteps)
}

@Test
@MainActor
func practiceEntryBlockingReasonIsMissingStoredCalibrationWhenStepsExist() {
    let appModel = AppModel()
    appModel.setImportedSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        file: nil
    )

    let viewModel = ARGuideViewModel(appModel: appModel)
    #expect(viewModel.practiceEntryBlockingReason() == .missingStoredCalibration)
}

@Test
@MainActor
func practiceEntryBlockingReasonIsNilWhenPreconditionsAreReady() {
    let appModel = AppModel()
    appModel.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )
    appModel.setImportedSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        file: nil
    )

    let viewModel = ARGuideViewModel(appModel: appModel)
    #expect(viewModel.practiceEntryBlockingReason() == nil)
}

@Test
@MainActor
func timeoutFailureMapsAnchorNotTrackedWithFiveSeconds() {
    let appModel = AppModel()
    let viewModel = ARGuideViewModel(appModel: appModel)
    let anchorID = UUID()

    let failure = viewModel.practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: .anchorNotTracked(id: anchorID)
    )

    #expect(failure == .anchorNotTracked(id: anchorID, waitedSeconds: 5))
}

@Test
@MainActor
func timeoutFailureMapsAnchorMissing() {
    let appModel = AppModel()
    let viewModel = ARGuideViewModel(appModel: appModel)
    let anchorID = UUID()

    let failure = viewModel.practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: .anchorMissing(id: anchorID)
    )

    #expect(failure == .anchorMissing(id: anchorID))
}

@Test
@MainActor
func timeoutFailureFallsBackToProviderStateSummary() {
    let appModel = AppModel()
    let viewModel = ARGuideViewModel(appModel: appModel)

    let failure = viewModel.practiceLocalizationTimeoutFailure(lastRecoverableResolution: nil)

    switch failure {
    case .providerNotRunning(let state):
        #expect(state.contains("world="))
        #expect(state.contains("hand="))
    default:
        #expect(Bool(false), "Expected providerNotRunning, got \(failure)")
    }
}

@Test
@MainActor
func anchorsTooCloseFailureHasActionableMessage() {
    let failure = ARGuideViewModel.PracticeLocalizationFailure.anchorsTooClose(distanceMeters: 0.0123)
    #expect(failure.message.contains("距离过近"))
    #expect(failure.message.contains("Step 1"))
}
