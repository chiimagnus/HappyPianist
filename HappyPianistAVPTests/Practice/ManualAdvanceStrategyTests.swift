import Foundation
@testable import HappyPianistAVP
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
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
            PracticeStep(tick: 240, notes: [PracticeStepNote(midiNote: 62, staff: 1, handAssignment: .unknown)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 64, staff: 1, handAssignment: .unknown)]),
            PracticeStep(tick: 1440, notes: [PracticeStepNote(midiNote: 65, staff: 1, handAssignment: .unknown)]),
        ],
        measureSpans: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 2, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 3, sourceMeasureIndex: 3, sourceMeasureNumberToken: "3", occurrenceIndex: 2, startTick: 960, endTick: 1440),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 4, sourceMeasureIndex: 4, sourceMeasureNumberToken: "4", occurrenceIndex: 3, startTick: 1440, endTick: 1920),
        ],
        activeRange: nil
    )
}

@Test
@MainActor
func appStatePassesMeasureSpansToPracticeSession() async {
    let playbackService = ManualAdvanceNoopPlaybackService()
    let sessionViewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: ManualAdvanceNoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playbackService,
        manualAdvanceMode: .measure
    )
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let guideViewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: SinglePracticeSessionViewModelProvider(session: sessionViewModel).callAsFunction
    )
    #expect(guideViewModel.practiceSessionViewModel === sessionViewModel)
    let prepared = makeTestPreparedPractice(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
        performanceNotes: [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 240),
            TestScorePerformanceNote(midiNote: 64, onTick: 480),
        ],
        measureSpans: [
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
            MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 2, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        ]
    )
    practiceSetupState.setImportedSteps(from: prepared)
    _ = await guideViewModel.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .freshDefaults,
        isCurrent: { true }
    )

    // First "next" begins the practice session at step 1.
    sessionViewModel.skip()
    // Next advances by measure.
    sessionViewModel.skip()

    #expect(sessionViewModel.currentStepIndex == 2)
    #expect(sessionViewModel.notationViewportTick() == 480)
}

@MainActor
private final class SinglePracticeSessionViewModelProvider: @unchecked Sendable {
    private let session: PracticeSessionViewModel

    init(session: PracticeSessionViewModel) {
        self.session = session
    }

    @MainActor
    func callAsFunction(_: String?) -> PracticeSessionViewModel {
        session
    }
}

private final class ManualAdvanceNoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], at _: PerformanceMonotonicInstant) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

private final class ManualAdvanceNoopPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}
