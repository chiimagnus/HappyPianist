import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func practiceEntryBlockingReasonIsMissingImportedStepsFirst() {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    appState.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )

    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
    #expect(viewModel.practiceEntryBlockingReason() == .missingImportedSteps)
}

@Test
@MainActor
func practiceEntryBlockingReasonIsMissingStoredCalibrationWhenStepsExist() {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    practiceSetupState.setImportedSteps(from: PreparedPractice(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])],
        file: ImportedMusicXMLFile(fileName: "Test", storedURL: URL(fileURLWithPath: "/dev/null"), importedAt: Date()),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        highlightGuides: [],
        measureSpans: [MusicXMLMeasureSpan(
            partID: "P1",
            measureNumber: 1,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            occurrenceIndex: 0,
            startTick: 0,
            endTick: 1
        )],
        unsupportedNoteCount: 0
    ))

    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
    #expect(viewModel.practiceEntryBlockingReason() == .missingStoredCalibration)
}

@Test
@MainActor
func practiceEntryBlockingReasonIsNilWhenPreconditionsAreReady() {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    appState.storedCalibration = StoredWorldAnchorCalibration(
        a0AnchorID: UUID(),
        c8AnchorID: UUID(),
        whiteKeyWidth: 0.0235
    )
    practiceSetupState.setImportedSteps(from: PreparedPractice(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])],
        file: ImportedMusicXMLFile(fileName: "Test", storedURL: URL(fileURLWithPath: "/dev/null"), importedAt: Date()),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        highlightGuides: [],
        measureSpans: [MusicXMLMeasureSpan(
            partID: "P1",
            measureNumber: 1,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            occurrenceIndex: 0,
            startTick: 0,
            endTick: 1
        )],
        unsupportedNoteCount: 0
    ))

    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
    #expect(viewModel.practiceEntryBlockingReason() == nil)
}

@Test
@MainActor
func timeoutFailureMapsAnchorNotTrackedWithFiveSeconds() {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
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
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
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
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)

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
