import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func resetToPreparationClearsPracticeSetupState() {
    let practiceSetupState = PracticeSetupState()
    practiceSetupState.selectedPianoModeID = "dummy"
    practiceSetupState.isCalibrationCompleted = true
    practiceSetupState.isVirtualPianoPlaced = true
    practiceSetupState.bluetoothMIDISourceCount = 2
    practiceSetupState.importErrorMessage = "error"
    practiceSetupState.setImportedSteps(from: PreparedPractice(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)])],
        file: ImportedMusicXMLFile(fileName: "Test", storedURL: URL(fileURLWithPath: "/dev/null"), importedAt: Date()),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        slurTimeline: nil,
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

    let registry = PianoModeRegistryService(modes: [])
    let service = WindowTransitionState(practiceSetupState: practiceSetupState, pianoModeRegistry: registry)
    service.resetToPreparation(reason: "test")

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
func consumePendingTransitionReturnsAndClears() {
    let service = WindowTransitionState(
        practiceSetupState: PracticeSetupState(),
        pianoModeRegistry: PianoModeRegistryService(modes: [])
    )

    service.beginTransition(from: .library, to: .practice)

    let transition = service.consumePendingTransition(to: .practice)
    #expect(transition?.fromWindowID == WindowID.library)
    #expect(transition?.toWindowID == WindowID.practice)
    #expect(service.consumePendingTransition(to: .practice) == nil)
}
