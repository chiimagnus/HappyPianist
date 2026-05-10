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
func selectPianoKindSetsRouteToRealPreparation() {
    let router = AppRouter(flowState: FlowState())
    router.selectPianoKind(.real)
    #expect(router.route == .realPreparation)
    #expect(router.flowState.pianoKind == .real)
}

@Test
@MainActor
func selectPianoKindSetsRouteToVirtualPreparation() {
    let router = AppRouter(flowState: FlowState())
    router.selectPianoKind(.virtual)
    #expect(router.route == .virtualPreparation)
    #expect(router.flowState.pianoKind == .virtual)
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

    router.selectPianoKind(.real)
    flowState.isCalibrationCompleted = true
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
    #expect(flowState.pianoKind == nil)
    #expect(flowState.isCalibrationCompleted == false)
    #expect(flowState.isVirtualPianoPlaced == false)
    #expect(flowState.importedSteps.isEmpty)
    #expect(flowState.importedFile == nil)
}

@Test
@MainActor
func canProceedToLibraryIsFalseWhenNoPianoKindSelected() {
    let router = AppRouter(flowState: FlowState())
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForRealWhenNotCalibrated() {
    let router = AppRouter(flowState: FlowState())
    router.selectPianoKind(.real)
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForRealWhenCalibrated() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)
    router.selectPianoKind(.real)
    flowState.isCalibrationCompleted = true
    #expect(router.canProceedToLibrary == true)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForVirtualWhenNotPlaced() {
    let router = AppRouter(flowState: FlowState())
    router.selectPianoKind(.virtual)
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForVirtualWhenPlaced() {
    let flowState = FlowState()
    let router = AppRouter(flowState: flowState)
    router.selectPianoKind(.virtual)
    flowState.isVirtualPianoPlaced = true
    #expect(router.canProceedToLibrary == true)
}
