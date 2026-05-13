import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func defaultRouteIsTypePicker() {
    let router = AppRouter(flowState: FlowState())
    #expect(router.route == .typePicker)
}

@Test
@MainActor
func selectPianoModeSetsRouteToPreparationForRealAudio() {
    let router = AppRouter(flowState: FlowState())
    let mode = RealAudioPianoMode()
    router.selectPianoMode(mode)
    #expect(router.route == .preparation)
    #expect(router.flowState.selectedPianoModeID == mode.id)
}

@Test
@MainActor
func selectPianoModeSetsRouteToPreparationForBluetoothMIDI() {
    let router = AppRouter(flowState: FlowState())
    let mode = BluetoothMIDIPianoMode()
    router.selectPianoMode(mode)
    #expect(router.route == .preparation)
    #expect(router.flowState.selectedPianoModeID == mode.id)
}

@Test
@MainActor
func selectPianoModeSetsRouteToPreparationForVirtualPiano() {
    let router = AppRouter(flowState: FlowState())
    let mode = VirtualPianoMode()
    router.selectPianoMode(mode)
    #expect(router.route == .preparation)
    #expect(router.flowState.selectedPianoModeID == mode.id)
}

@Test
@MainActor
func goToLibrarySetsRoute() {
    let router = AppRouter(flowState: FlowState())
    router.goToLibrary()
    #expect(router.route == .library)
}

@Test
@MainActor
func goToPracticeSetsRoute() {
    let router = AppRouter(flowState: FlowState())
    router.goToPractice()
    #expect(router.route == .practice)
}

@Test
@MainActor
func exitToTypePickerResetsRouteAndFlowState() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)

    router.selectPianoMode(RealAudioPianoMode())
    flowState.isCalibrationCompleted = true
    flowState.bluetoothMIDISourceCount = 2
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

    router.exitToTypePicker(reason: "test")

    #expect(router.route == .typePicker)
    #expect(flowState.selectedPianoModeID == nil)
    #expect(flowState.isCalibrationCompleted == false)
    #expect(flowState.isVirtualPianoPlaced == false)
    #expect(flowState.bluetoothMIDISourceCount == 0)
    #expect(flowState.importedSteps.isEmpty)
    #expect(flowState.importedFile == nil)
}

@Test
@MainActor
func canProceedToLibraryIsFalseWhenNoPianoModeSelected() {
    let router = AppRouter(flowState: FlowState())
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForRealAudioWhenNotCalibrated() {
    let router = AppRouter(flowState: FlowState())
    router.selectPianoMode(RealAudioPianoMode())
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForRealAudioWhenCalibrated() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)
    router.selectPianoMode(RealAudioPianoMode())
    flowState.isCalibrationCompleted = true
    #expect(router.canProceedToLibrary == true)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForBluetoothMIDIWhenNoSources() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)
    router.selectPianoMode(BluetoothMIDIPianoMode())
    flowState.isCalibrationCompleted = true
    flowState.bluetoothMIDISourceCount = 0
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForBluetoothMIDIWhenCalibratedAndHasSources() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)
    router.selectPianoMode(BluetoothMIDIPianoMode())
    flowState.isCalibrationCompleted = true
    flowState.bluetoothMIDISourceCount = 1
    #expect(router.canProceedToLibrary == true)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForVirtualWhenNotPlaced() {
    let router = AppRouter(flowState: FlowState())
    router.selectPianoMode(VirtualPianoMode())
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForVirtualWhenPlaced() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)
    router.selectPianoMode(VirtualPianoMode())
    flowState.isVirtualPianoPlaced = true
    #expect(router.canProceedToLibrary == true)
}
