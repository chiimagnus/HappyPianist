import Foundation
import Observation

@dynamicMemberLookup
@MainActor
@Observable
final class PracticeSessionViewModel: PracticeSessionEffectHandlerProtocol {
    enum SessionRecorderEvent {
        case guiding(Bool)
        case settingsPresented(Bool)
        case checkpoint
        case configureAnalysis(
            plan: ScorePerformancePlan,
            measureSpans: [MusicXMLMeasureSpan],
            activeTickRange: Range<Int>?,
            tempoScale: Double
        )
        case inputCapabilitiesAvailable(PerformanceInputCapabilities)
        case resetAnalysis
    }

    let stateStore: PracticeSessionStateStore
    let stepNavigator: PracticeStepNavigator

    let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    let sleeper: SleeperProtocol
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    let playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol
    let keyContactDetectionService: any KeyContactDetectingProtocol
    let realPianoContactDetectionService: any KeyContactDetectingProtocol
    let handObservationSourceKind: PerformanceObservation.Source.Kind?
    let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    let practiceInputEventSource: PracticeInputEventSourceProtocol?
    let audioStepAttemptAccumulator: AudioStepAttemptAccumulator
    let midiPracticeStepMatcher: any MIDIPracticeStepMatchingProtocol
    let settingsProvider: any PracticeSessionSettingsProviderProtocol
    let attemptReducer = PracticeAttemptReducer()
    let roundConfigurationController: PracticeRoundConfigurationController
    let progressCoordinator: PracticeProgressCoordinator?
    let sessionRecorder: PracticeSessionRecorder?
    let diagnosticsReporter: (any DiagnosticsReporting)?
    let coachingDecisionService: CoachingDecisionService
    let feedbackPolicy = PracticeFeedbackPolicy()

    var practiceMIDIInputService: PracticeMIDIInputService?
    var audioRecognitionInputService: PracticeAudioRecognitionInputService?
    var playbackControlService: PracticePlaybackControlService?
    var manualReplayService: PracticeManualReplayService?
    var highlightGuideController: PracticeHighlightGuideController?
    var handGateController: PracticeHandGateController?
    var virtualPianoInputController: VirtualPianoInputController?

    let handPianoActivityGate: HandPianoActivityGate

    let audioRecognitionSuppressDuration: TimeInterval = 0.6
    let autoplayTimingLeadInSeconds: TimeInterval = 0.05

    private(set) var hasShutdown = false
    private(set) var guidingStartIsBlocked = false
    var lastProgressRestoreOutcome: PracticeProgressRestoreOutcome = .none
    @ObservationIgnored var sessionRecorderEventTask: Task<Void, Never>?
    @ObservationIgnored var performanceAssessmentLifecycleGeneration = 0
    @ObservationIgnored var handObservationRecordingTask: Task<Void, Never>?
    @ObservationIgnored var hasRegisteredHandCapabilities = false
    @ObservationIgnored var autoplayTimelineBuildTask: Task<Void, Never>?
    @ObservationIgnored var autoplayTimelineBuildGeneration = 0

    var practiceHandMode: PracticeHandMode {
        stateStore.activeRoundConfiguration?.handMode ?? .both
    }

    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<PracticeSessionStateStore, Value>) -> Value {
        get { stateStore[keyPath: keyPath] }
        set { stateStore[keyPath: keyPath] = newValue }
    }

    init(
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        playbackSequenceBuilder: (any PlaybackSequenceBuildingProtocol)? = nil,
        keyContactDetectionService: (any KeyContactDetectingProtocol)? = nil,
        realPianoContactDetectionService: (any KeyContactDetectingProtocol)? = nil,
        handObservationSourceKind: PerformanceObservation.Source.Kind? = nil,
        midiPracticeStepMatcher: (any MIDIPracticeStepMatchingProtocol)? = nil,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        practiceInputEventSource: PracticeInputEventSourceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator,
        handPianoActivityGate: HandPianoActivityGate,
        settingsProvider: (any PracticeSessionSettingsProviderProtocol)? = nil,
        roundDefaultsStore: (any PracticeRoundDefaultsStoreProtocol)? = nil,
        progressCoordinator: PracticeProgressCoordinator? = nil,
        sessionRecorder: PracticeSessionRecorder? = nil,
        coachingDecisionService: CoachingDecisionService? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        stateStore = PracticeSessionStateStore()
        stepNavigator = PracticeStepNavigator()

        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService
        self.playbackSequenceBuilder = playbackSequenceBuilder ?? PlaybackSequenceBuilder()
        self.keyContactDetectionService = keyContactDetectionService ?? KeyContactDetectionService()
        self.realPianoContactDetectionService = realPianoContactDetectionService ?? RealPianoContactDetectionService()
        self.handObservationSourceKind = handObservationSourceKind
        self.audioRecognitionService = audioRecognitionService
        self.practiceInputEventSource = practiceInputEventSource
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator
        self.midiPracticeStepMatcher = midiPracticeStepMatcher ?? MIDIPracticeStepMatcher()
        self.handPianoActivityGate = handPianoActivityGate
        let resolvedSettingsProvider = settingsProvider ?? UserDefaultsPracticeSessionSettingsProvider()
        self.settingsProvider = resolvedSettingsProvider
        self.progressCoordinator = progressCoordinator
        self.sessionRecorder = sessionRecorder
        self.coachingDecisionService = coachingDecisionService
            ?? CoachingDecisionService(diagnosticsReporter: diagnosticsReporter)
        self.diagnosticsReporter = diagnosticsReporter
        roundConfigurationController = PracticeRoundConfigurationController(
            stateStore: stateStore,
            settingsProvider: resolvedSettingsProvider,
            defaultsStore: roundDefaultsStore ?? UserDefaultsPracticeRoundDefaultsStore()
        )

        practiceMIDIInputService = PracticeMIDIInputService(
            practiceInputEventSource: practiceInputEventSource,
            matcher: self.midiPracticeStepMatcher,
            stateStore: stateStore,
            effectHandler: self,
            diagnosticsReporter: diagnosticsReporter,
            observationRecorder: sessionRecorder,
            consumeEvents: true
        )
        audioRecognitionInputService = PracticeAudioRecognitionInputService(
            service: audioRecognitionService,
            accumulator: audioStepAttemptAccumulator,
            stateStore: stateStore,
            effectHandler: self,
            diagnosticsReporter: diagnosticsReporter,
            observationRecorder: sessionRecorder,
            consumeStreams: true
        )

        playbackControlService = PracticePlaybackControlService(
            sleeper: sleeper,
            sequencerPlaybackService: sequencerPlaybackService,
            playbackSequenceBuilder: self.playbackSequenceBuilder,
            chordAttemptAccumulator: chordAttemptAccumulator,
            stateStore: stateStore,
            audioRecognitionService: audioRecognitionService,
            effectHandler: self,
            audioRecognitionSuppressDuration: audioRecognitionSuppressDuration,
            leadInSeconds: autoplayTimingLeadInSeconds,
            diagnosticsReporter: diagnosticsReporter
        )

        manualReplayService = PracticeManualReplayService(
            sleeper: sleeper,
            sequencerPlaybackService: sequencerPlaybackService,
            playbackSequenceBuilder: self.playbackSequenceBuilder,
            stateStore: stateStore,
            effectHandler: self,
            diagnosticsReporter: diagnosticsReporter
        )

        highlightGuideController = PracticeHighlightGuideController(
            sleeper: sleeper,
            stateStore: stateStore
        )

        let handGateController = PracticeHandGateController(
            activityGate: handPianoActivityGate,
            chordAttemptAccumulator: chordAttemptAccumulator,
            stateStore: stateStore,
            effectHandler: self
        )
        self.handGateController = handGateController
        virtualPianoInputController = VirtualPianoInputController(
            detector: self.keyContactDetectionService,
            sequencerPlaybackService: sequencerPlaybackService,
            stateStore: stateStore,
            handGateController: handGateController
        )
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        enqueueSessionRecorderEvent(.resetAnalysis)

        cancelAutoplayTimelineBuild()
        stopManualReplayTask(restoreAudioRecognition: false)
        playbackControlService?.shutdown()
        handle(effect: .stopAudioRecognition)
        handle(effect: .stopPracticeInput)

        audioRecognitionInputService?.shutdown()
        practiceMIDIInputService?.shutdown()
        highlightGuideController?.shutdown()
        manualReplayService?.shutdown()
        handGateController?.shutdown()
        virtualPianoInputController?.shutdown()
    }

    func setGuidingStartBlocked(_ isBlocked: Bool) {
        guidingStartIsBlocked = isBlocked
    }

    func enqueueSessionRecorderEvent(_ event: SessionRecorderEvent) {
        let resetsCoaching: Bool
        switch event {
        case .configureAnalysis:
            performanceAssessmentLifecycleGeneration += 1
            self.currentCoachingDecision = nil
            resetsCoaching = false
        case .resetAnalysis:
            performanceAssessmentLifecycleGeneration += 1
            self.currentCoachingDecision = nil
            resetsCoaching = true
        case .guiding, .settingsPresented, .checkpoint, .inputCapabilitiesAvailable:
            resetsCoaching = false
        }
        guard sessionRecorder != nil || resetsCoaching else { return }
        let previousTask = sessionRecorderEventTask
        let sessionRecorder = sessionRecorder
        let coachingDecisionService = coachingDecisionService
        sessionRecorderEventTask = Task { @MainActor in
            await previousTask?.value
            if resetsCoaching {
                await coachingDecisionService.reset()
            }
            guard let sessionRecorder else { return }
            switch event {
            case let .guiding(isGuiding):
                if isGuiding == false {
                    await waitForPendingPerformanceObservationRecording()
                }
                await sessionRecorder.setGuiding(isGuiding)
            case let .settingsPresented(isPresented):
                await sessionRecorder.setSettingsPresented(isPresented)
            case .checkpoint:
                await sessionRecorder.checkpoint()
            case let .configureAnalysis(plan, measureSpans, activeTickRange, tempoScale):
                await sessionRecorder.configureAnalysis(
                    plan: plan,
                    measureSpans: measureSpans,
                    activeTickRange: activeTickRange,
                    tempoScale: tempoScale
                )
            case let .inputCapabilitiesAvailable(capabilities):
                await sessionRecorder.registerInputCapabilities(capabilities)
            case .resetAnalysis:
                await sessionRecorder.resetAnalysis()
            }
        }
    }

    func waitForSessionRecorderEvents() async {
        await sessionRecorderEventTask?.value
    }

    func waitForPendingPerformanceObservationRecording() async {
        await practiceMIDIInputService?.waitForPendingObservationRecording()
        await audioRecognitionInputService?.waitForPendingObservationRecording()
        await handObservationRecordingTask?.value
    }

    func handle(effect: PracticeSessionEffect) {
        switch effect {
        case let .attemptEvaluated(outcome):
            guard self.acceptsPracticeAttempts, case .guiding = self.state else { return }
            recordAttemptOutcome(outcome)
        case .advanceToNextStep:
            guard self.acceptsPracticeAttempts, case .guiding = self.state else { return }
            advanceToNextStep()
        case .refreshPracticeInput:
            refreshPracticeInputForCurrentState()
        case .refreshAudioRecognition:
            refreshAudioRecognitionForCurrentState()
        case .stopTransientWork:
            stopManualReplayTask()
            playbackControlService?.stopTransientWork()
        case .stopAudioRecognition:
            stopAudioRecognition()
        case .stopPracticeInput:
            stopPracticeInput()
        case let .inputCapabilitiesAvailable(capabilities):
            enqueueSessionRecorderEvent(.inputCapabilitiesAvailable(capabilities))
        }
    }
}
