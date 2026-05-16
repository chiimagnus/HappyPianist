@testable import LonelyPianistAVP
import Foundation
import Testing

@Test
@MainActor
func resetToPreparationClearsFlowState() {
    let flowState = FlowState()
    flowState.selectedPianoModeID = "dummy"
    flowState.isCalibrationCompleted = true
    flowState.isVirtualPianoPlaced = true
    flowState.bluetoothMIDISourceCount = 2
    flowState.importErrorMessage = "error"
    flowState.setImportedSteps(from: PreparedPractice(
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)])],
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

    let registry = PianoModeRegistryService(modes: [])
    let coordinator = WindowCoordinator(flowState: flowState, pianoModeRegistry: registry)
    coordinator.resetToPreparation(reason: "test")

    #expect(flowState.selectedPianoModeID == nil)
    #expect(flowState.isCalibrationCompleted == false)
    #expect(flowState.isVirtualPianoPlaced == false)
    #expect(flowState.bluetoothMIDISourceCount == 0)
    #expect(flowState.importedSteps.isEmpty)
    #expect(flowState.importedFile == nil)
    #expect(flowState.importErrorMessage == nil)
}

@Test
@MainActor
func transitionCallsOpenThenDismiss() {
    let coordinator = WindowCoordinator(flowState: FlowState(), pianoModeRegistry: PianoModeRegistryService(modes: []))

    var events: [String] = []
    coordinator.transition(
        from: .library,
        to: .practice,
        open: { id in events.append("open:\(id)") },
        dismiss: { id in
            let idText = id ?? "nil"
            events.append("dismiss:\(idText)")
        }
    )

    #expect(events == ["open:\(WindowIDs.practice)", "dismiss:\(WindowIDs.library)"])
}

@Test
@MainActor
func transitionDismissesNilWhenCurrentUnknown() {
    let coordinator = WindowCoordinator(flowState: FlowState(), pianoModeRegistry: PianoModeRegistryService(modes: []))

    var events: [String] = []
    coordinator.transition(
        from: nil,
        to: .library,
        open: { id in events.append("open:\(id)") },
        dismiss: { id in
            let idText = id ?? "nil"
            events.append("dismiss:\(idText)")
        }
    )

    #expect(events == ["open:\(WindowIDs.library)", "dismiss:nil"])
}

@Test
@MainActor
func transitionNoopsWhenTargetEqualsCurrent() {
    let coordinator = WindowCoordinator(flowState: FlowState(), pianoModeRegistry: PianoModeRegistryService(modes: []))

    var events: [String] = []
    coordinator.transition(
        from: .practice,
        to: .practice,
        open: { id in events.append("open:\(id)") },
        dismiss: { id in
            let idText = id ?? "nil"
            events.append("dismiss:\(idText)")
        }
    )

    #expect(events.isEmpty)
}
