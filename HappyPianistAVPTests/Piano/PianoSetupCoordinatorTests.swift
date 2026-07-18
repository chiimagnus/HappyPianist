import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func resetPianoSetupClearsPracticeSetupState() {
    let practiceSetupState = PracticeSetupState()
    practiceSetupState.selectedPianoModeID = "dummy"
    practiceSetupState.isCalibrationCompleted = true
    practiceSetupState.isVirtualPianoPlaced = true
    practiceSetupState.bluetoothMIDISourceCount = 2
    practiceSetupState.importErrorMessage = "error"
    practiceSetupState.setImportedSteps(from: PreparedPractice(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil, handAssignment: .unknown)])],
        file: ImportedMusicXMLFile(
            fileName: "Test",
            storedURL: URL(fileURLWithPath: "/dev/null"),
            importedAt: Date()
        ),
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
        unsupportedNoteCount: 0,
        scoreContext: makeTestPreparedPracticeScoreContext()
    ))

    let registry = PianoModeRegistryService(modes: [])
    let coordinator = PianoSetupCoordinator(
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: registry
    )
    coordinator.reset()

    #expect(practiceSetupState.selectedPianoModeID == nil)
    #expect(practiceSetupState.isCalibrationCompleted == false)
    #expect(practiceSetupState.isVirtualPianoPlaced == false)
    #expect(practiceSetupState.bluetoothMIDISourceCount == 0)
    #expect(practiceSetupState.importedSteps.isEmpty)
    #expect(practiceSetupState.importedFile == nil)
    #expect(practiceSetupState.importErrorMessage == nil)
}

@Test
@MainActor
func setupReadinessUsesOnlySelectedModeRequirements() {
    let state = PracticeSetupState()
    let coordinator = PianoSetupCoordinator(
        practiceSetupState: state,
        pianoModeRegistry: PianoModeRegistryService(
            modes: PianoModeCatalogService.makeDefaultModes()
        )
    )

    #expect(coordinator.isSetupReady == false)

    state.selectedPianoModeID = PianoModeID.realAudio.rawValue
    #expect(coordinator.isSetupReady == false)
    state.isCalibrationCompleted = true
    #expect(coordinator.isSetupReady)

    state.selectedPianoModeID = PianoModeID.bluetoothMIDI.rawValue
    #expect(coordinator.isSetupReady == false)
    state.bluetoothMIDISourceCount = 1
    #expect(coordinator.isSetupReady)

    state.selectedPianoModeID = PianoModeID.virtualPiano.rawValue
    #expect(coordinator.isSetupReady == false)
    state.isVirtualPianoPlaced = true
    #expect(coordinator.isSetupReady)
}
