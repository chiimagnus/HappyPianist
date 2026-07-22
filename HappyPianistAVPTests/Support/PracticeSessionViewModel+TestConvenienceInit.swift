import Foundation
@testable import HappyPianistAVP

extension PracticeSessionViewModel {
    @MainActor
    convenience init(
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol? = nil,
        realPianoContactDetectionService: (any KeyContactDetectingProtocol)? = nil,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        practiceInputEventSource: PracticeInputEventSourceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator? = nil,
        handPianoActivityGate: HandPianoActivityGate? = nil,
        progressCoordinator: PracticeProgressCoordinator? = nil,
        sessionRecorder: PracticeSessionRecorder? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        manualAdvanceMode: ManualAdvanceMode = .step
    ) {
        let resolvedPlaybackService = sequencerPlaybackService ?? NoopPracticeSequencerPlaybackService()
        let resolvedAudioStepAttemptAccumulator = audioStepAttemptAccumulator ?? AudioStepAttemptAccumulator()
        let resolvedHandPianoActivityGate = handPianoActivityGate ?? HandPianoActivityGate()
        let settingsProvider = TestPracticeSessionSettingsProvider(
            manualAdvanceMode: manualAdvanceMode
        )
        self.init(
            chordAttemptAccumulator: chordAttemptAccumulator,
            sleeper: sleeper,
            sequencerPlaybackService: resolvedPlaybackService,
            realPianoContactDetectionService: realPianoContactDetectionService,
            audioRecognitionService: audioRecognitionService,
            practiceInputEventSource: practiceInputEventSource,
            audioStepAttemptAccumulator: resolvedAudioStepAttemptAccumulator,
            handPianoActivityGate: resolvedHandPianoActivityGate,
            settingsProvider: settingsProvider,
            roundDefaultsStore: TestPracticeRoundDefaultsStore(),
            progressCoordinator: progressCoordinator,
            sessionRecorder: sessionRecorder,
            diagnosticsReporter: diagnosticsReporter
        )
    }
}

private struct TestPracticeSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode
    let practiceHandMode: PracticeHandMode = .both
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private struct TestPracticeRoundDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    let tempoScale = 0.6
    let loopEnabled = true
    let requiredSuccesses = 3

    func save(
        handMode _: PracticeHandMode,
        manualAdvanceMode _: ManualAdvanceMode,
        soundRoutingSettings _: PracticeSoundRoutingSettings,
        tempoScale _: Double,
        loopEnabled _: Bool,
        requiredSuccesses _: Int
    ) {}
}

private let defaultTestPracticeSongIdentity = PracticeSongIdentity(
    songID: UUID(),
    scoreRevision: "test-score"
)

extension PracticeSessionViewModel {
    @MainActor
    func installTestPerformanceNotes(
        _ notes: [TestScorePerformanceNote],
        tempoEvents: [ScorePerformanceTempoEvent] = [],
        controllerEvents: [ScorePerformanceControllerEvent] = [],
        annotations: [ScorePerformanceAnnotation] = [],
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        highlightGuides: [PianoHighlightGuide] = [],
        measureSpans: [MusicXMLMeasureSpan] = []
    ) {
        let identity = self.songIdentity ?? defaultTestPracticeSongIdentity
        let sourceScore = makeTestMusicXMLScore(notes: notes)
        let scoreContext = makeTestPreparedPracticeScoreContext(sourceScore: sourceScore)
        let plan = makeTestScorePerformancePlan(
            identity: identity,
            notes: notes,
            scoreContext: scoreContext,
            tempoEvents: tempoEvents,
            controllerEvents: controllerEvents,
            annotations: annotations
        )
        installTestPerformancePlan(
            plan,
            sourceScore: sourceScore,
            attributeTimeline: attributeTimeline,
            highlightGuides: highlightGuides,
            measureSpans: measureSpans
        )
    }

    @MainActor
    func installTestPerformancePlan(
        _ plan: ScorePerformancePlan,
        sourceScore: MusicXMLScore = MusicXMLScore(notes: []),
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        highlightGuides: [PianoHighlightGuide] = [],
        measureSpans: [MusicXMLMeasureSpan] = []
    ) {
        let steps = PracticeStepBuilder().buildSteps(from: plan).steps
        let resolvedMeasureSpans = measureSpans.isEmpty
            ? [Self.syntheticMeasureSpan(for: steps)]
            : measureSpans
        let identity = self.songIdentity ?? PracticeSongIdentity(
            songID: plan.sourceScoreIdentity.songID,
            scoreRevision: plan.sourceScoreIdentity.scoreRevision
        )
        installPreparedSteps(
            steps,
            identity: identity,
            performancePlan: plan,
            notationProjection: ScoreNotationProjection(plan: plan, sourceScore: sourceScore),
            attributeTimeline: attributeTimeline,
            highlightGuides: highlightGuides,
            measureSpans: resolvedMeasureSpans
        )
    }

    private static func syntheticMeasureSpan(for steps: [PracticeStep]) -> MusicXMLMeasureSpan {
        let startTick = steps.map(\.tick).min() ?? 0
        let finalTick = steps.map(\.tick).max() ?? startTick
        return MusicXMLMeasureSpan(
            partID: "test-part",
            measureNumber: 1,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            occurrenceIndex: 0,
            startTick: startTick,
            endTick: finalTick + 1
        )
    }
}
