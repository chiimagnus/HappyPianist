import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func measureNextStepFromMeasureStartJumpsToNextMeasureStart() {
    let strategy = MeasureManualAdvanceStrategy()
    let context = makeManualAdvanceContext(currentStepIndex: 0)
    #expect(strategy.nextStepIndex(in: context) == 2)
}

@Test
func measureNextStepFromMiddleJumpsToNextMeasureStart() {
    let strategy = MeasureManualAdvanceStrategy()
    let context = makeManualAdvanceContext(currentStepIndex: 1)
    #expect(strategy.nextStepIndex(in: context) == 2)
}

@Test
func measureNextStepSkipsEmptyMeasureToFollowingStep() {
    let strategy = MeasureManualAdvanceStrategy()
    let context = makeManualAdvanceContext(currentStepIndex: 2)
    #expect(strategy.nextStepIndex(in: context) == 3)
}

@Test
func measureNextStepFromLastMeasureCompletes() {
    let strategy = MeasureManualAdvanceStrategy()
    let context = makeManualAdvanceContext(currentStepIndex: 3)
    #expect(strategy.nextStepIndex(in: context) == nil)
}

private func makeManualAdvanceContext(currentStepIndex: Int) -> ManualAdvanceContext {
    ManualAdvanceContext(
        currentStepIndex: currentStepIndex,
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 64, staff: 1)]),
            PracticeStep(tick: 1440, notes: [PracticeStepNote(midiNote: 65, staff: 1)]),
        ],
        measureSpans: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 480),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, startTick: 480, endTick: 960),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 3, startTick: 960, endTick: 1440),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 4, startTick: 1440, endTick: 1920),
        ]
    )
}

@Test
@MainActor
func appStatePassesMeasureSpansToPracticeSession() {
    let playbackService = ManualAdvanceNoopPlaybackService()
    let sessionViewModel = PracticeSessionViewModel(
        pressDetectionService: ManualAdvanceNoopPressDetectionService(),
        chordAttemptAccumulator: ManualAdvanceNoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        manualAdvanceModeProvider: { .measure }
    )
    let appState = AppState()
    let guideViewModel = ARGuideViewModel(appState: appState, practiceSessionViewModel: sessionViewModel)
    appState.setImportedSteps(from: PreparedPractice(
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 64, staff: 1)]),
        ],
        file: ImportedMusicXMLFile(fileName: "Test", storedURL: URL(fileURLWithPath: "/dev/null"), importedAt: Date()),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        slurTimeline: nil,
        noteSpans: [],
        highlightGuides: [],
        measureSpans: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 480),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, startTick: 480, endTick: 960),
        ],
        unsupportedNoteCount: 0
    ))

    // First "next" begins the practice session at step 1.
    sessionViewModel.skip()
    // Next advances by measure.
    sessionViewModel.skip()

    #expect(sessionViewModel.currentStepIndex == 2)
}

private struct ManualAdvanceNoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class ManualAdvanceNoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], tolerance _: Int, at _: Date) -> Bool {
        false
    }

    func reset() {}
}

private final class ManualAdvanceNoopPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}
