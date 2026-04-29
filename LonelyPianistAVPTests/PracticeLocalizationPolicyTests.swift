import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func practiceEntryBlockingReasonIsMissingImportedStepsFirst() {
    let appState = AppState()
    appState.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )

    let viewModel = ARGuideViewModel(appState: appState)
    #expect(viewModel.practiceEntryBlockingReason() == .missingImportedSteps)
}

@Test
@MainActor
func practiceEntryBlockingReasonIsMissingStoredCalibrationWhenStepsExist() {
    let appState = AppState()
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

    let viewModel = ARGuideViewModel(appState: appState)
    #expect(viewModel.practiceEntryBlockingReason() == .missingStoredCalibration)
}

@Test
@MainActor
func practiceEntryBlockingReasonIsNilWhenPreconditionsAreReady() {
    let appState = AppState()
    appState.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )
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

    let viewModel = ARGuideViewModel(appState: appState)
    #expect(viewModel.practiceEntryBlockingReason() == nil)
}

@Test
@MainActor
func timeoutFailureMapsAnchorNotTrackedWithFiveSeconds() {
    let appState = AppState()
    let viewModel = ARGuideViewModel(appState: appState)
    let anchorID = UUID()

    let failure = viewModel.practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: .anchorNotTracked(id: anchorID)
    )

    #expect(failure == .anchorNotTracked(id: anchorID, waitedSeconds: 5))
}

@Test
@MainActor
func timeoutFailureMapsAnchorMissing() {
    let appState = AppState()
    let viewModel = ARGuideViewModel(appState: appState)
    let anchorID = UUID()

    let failure = viewModel.practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: .anchorMissing(id: anchorID)
    )

    #expect(failure == .anchorMissing(id: anchorID))
}

@Test
@MainActor
func timeoutFailureFallsBackToProviderStateSummary() {
    let appState = AppState()
    let viewModel = ARGuideViewModel(appState: appState)

    let failure = viewModel.practiceLocalizationTimeoutFailure(lastRecoverableResolution: nil)

    switch failure {
        case let .providerNotRunning(state):
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
