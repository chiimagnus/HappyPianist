import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func defaultRouteIsTypePicker() {
    let router = makeRouter(flowState: FlowState())
    #expect(router.route == .typePicker)
}

@Test
@MainActor
func selectPianoModeSetsRouteToPreparationForRealAudio() {
    let router = makeRouter(flowState: FlowState())
    let mode = RealAudioPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() })
    router.selectPianoMode(mode)
    #expect(router.route == .preparation)
    #expect(router.flowState.selectedPianoModeID == mode.id)
}

@Test
@MainActor
func selectPianoModeSetsRouteToPreparationForBluetoothMIDI() {
    let router = makeRouter(flowState: FlowState())
    let mode = BluetoothMIDIPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() })
    router.selectPianoMode(mode)
    #expect(router.route == .preparation)
    #expect(router.flowState.selectedPianoModeID == mode.id)
}

@Test
@MainActor
func selectPianoModeSetsRouteToPreparationForVirtualPiano() {
    let router = makeRouter(flowState: FlowState())
    let mode = VirtualPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() })
    router.selectPianoMode(mode)
    #expect(router.route == .preparation)
    #expect(router.flowState.selectedPianoModeID == mode.id)
}

@Test
@MainActor
func goToLibrarySetsRoute() {
    let router = makeRouter(flowState: FlowState())
    router.goToLibrary()
    #expect(router.route == .library)
}

@Test
@MainActor
func goToPracticeSetsRoute() {
    let router = makeRouter(flowState: FlowState())
    router.goToPractice()
    #expect(router.route == .practice)
}

@Test
@MainActor
func exitToTypePickerResetsRouteAndFlowState() {
    let flowState = FlowState()
    let router = makeRouter(flowState: flowState)

    router.selectPianoMode(RealAudioPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
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
    let router = makeRouter(flowState: FlowState())
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForRealAudioWhenNotCalibrated() {
    let router = makeRouter(flowState: FlowState())
    router.selectPianoMode(RealAudioPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForRealAudioWhenCalibrated() {
    let flowState = FlowState()
    let router = makeRouter(flowState: flowState)
    router.selectPianoMode(RealAudioPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
    flowState.isCalibrationCompleted = true
    #expect(router.canProceedToLibrary == true)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForBluetoothMIDIWhenNoSources() {
    let flowState = FlowState()
    let router = makeRouter(flowState: flowState)
    router.selectPianoMode(BluetoothMIDIPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
    flowState.isCalibrationCompleted = true
    flowState.bluetoothMIDISourceCount = 0
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForBluetoothMIDIWhenCalibratedAndHasSources() {
    let flowState = FlowState()
    let router = makeRouter(flowState: flowState)
    router.selectPianoMode(BluetoothMIDIPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
    flowState.isCalibrationCompleted = true
    flowState.bluetoothMIDISourceCount = 1
    #expect(router.canProceedToLibrary == true)
}

@Test
@MainActor
func canProceedToLibraryIsFalseForVirtualWhenNotPlaced() {
    let router = makeRouter(flowState: FlowState())
    router.selectPianoMode(VirtualPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
    #expect(router.canProceedToLibrary == false)
}

@Test
@MainActor
func canProceedToLibraryIsTrueForVirtualWhenPlaced() {
    let flowState = FlowState()
    let router = makeRouter(flowState: flowState)
    router.selectPianoMode(VirtualPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }))
    flowState.isVirtualPianoPlaced = true
    #expect(router.canProceedToLibrary == true)
}

@MainActor
private func makeRouter(flowState: FlowState) -> AppRouter {
    let registry = PianoModeRegistryService(modes: [
        RealAudioPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }),
        BluetoothMIDIPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }),
        VirtualPianoMode(makePracticeSessionViewModel: { dummyPracticeSessionViewModel() }),
    ])
    return AppRouter(flowState: flowState, pianoModeRegistry: registry)
}

@MainActor
private func dummyPracticeSessionViewModel() -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: PressDetectionService(),
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: NoopSequencerPlaybackService(),
        audioRecognitionService: nil,
        practiceInputEventSource: nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
        handPianoActivityGate: HandPianoActivityGate()
    )
}

@MainActor
private final class NoopSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}
