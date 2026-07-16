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
    }

    let stateStore: PracticeSessionStateStore
    let stepNavigator: PracticeStepNavigator

    let pressDetectionService: PressDetectionServiceProtocol
    let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    let sleeper: SleeperProtocol
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    let playbackSequenceBuilder: any PlaybackSequenceBuildingProtocol
    let keyContactDetectionService: any KeyContactDetectingProtocol
    let realPianoContactDetectionService: any KeyContactDetectingProtocol
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
    @ObservationIgnored private var sessionRecorderEventTask: Task<Void, Never>?

    var practiceHandMode: PracticeHandMode {
        stateStore.activeRoundConfiguration?.handMode ?? .both
    }

    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<PracticeSessionStateStore, Value>) -> Value {
        get { stateStore[keyPath: keyPath] }
        set { stateStore[keyPath: keyPath] = newValue }
    }

    init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        playbackSequenceBuilder: (any PlaybackSequenceBuildingProtocol)? = nil,
        keyContactDetectionService: (any KeyContactDetectingProtocol)? = nil,
        realPianoContactDetectionService: (any KeyContactDetectingProtocol)? = nil,
        midiPracticeStepMatcher: (any MIDIPracticeStepMatchingProtocol)? = nil,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        practiceInputEventSource: PracticeInputEventSourceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator,
        handPianoActivityGate: HandPianoActivityGate,
        settingsProvider: (any PracticeSessionSettingsProviderProtocol)? = nil,
        roundDefaultsStore: (any PracticeRoundDefaultsStoreProtocol)? = nil,
        progressCoordinator: PracticeProgressCoordinator? = nil,
        sessionRecorder: PracticeSessionRecorder? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        stateStore = PracticeSessionStateStore()
        stepNavigator = PracticeStepNavigator()

        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService
        self.playbackSequenceBuilder = playbackSequenceBuilder ?? PlaybackSequenceBuilder()
        self.keyContactDetectionService = keyContactDetectionService ?? KeyContactDetectionService()
        self.realPianoContactDetectionService = realPianoContactDetectionService ?? RealPianoContactDetectionService()
        self.audioRecognitionService = audioRecognitionService
        self.practiceInputEventSource = practiceInputEventSource
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator
        self.midiPracticeStepMatcher = midiPracticeStepMatcher ?? MIDIPracticeStepMatcher()
        self.handPianoActivityGate = handPianoActivityGate
        let resolvedSettingsProvider = settingsProvider ?? UserDefaultsPracticeSessionSettingsProvider()
        self.settingsProvider = resolvedSettingsProvider
        self.progressCoordinator = progressCoordinator
        self.sessionRecorder = sessionRecorder
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
            consumeEvents: true
        )
        audioRecognitionInputService = PracticeAudioRecognitionInputService(
            service: audioRecognitionService,
            accumulator: audioStepAttemptAccumulator,
            stateStore: stateStore,
            effectHandler: self,
            diagnosticsReporter: diagnosticsReporter,
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
            leadInSeconds: autoplayTimingLeadInSeconds
        )

        manualReplayService = PracticeManualReplayService(
            sleeper: sleeper,
            sequencerPlaybackService: sequencerPlaybackService,
            playbackSequenceBuilder: self.playbackSequenceBuilder,
            stateStore: stateStore,
            effectHandler: self
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
        guard let sessionRecorder else { return }
        let previousTask = sessionRecorderEventTask
        sessionRecorderEventTask = Task { @MainActor in
            await previousTask?.value
            switch event {
            case let .guiding(isGuiding):
                await sessionRecorder.setGuiding(isGuiding)
            case let .settingsPresented(isPresented):
                await sessionRecorder.setSettingsPresented(isPresented)
            case .checkpoint:
                await sessionRecorder.checkpoint()
            }
        }
    }

    func waitForSessionRecorderEvents() async {
        await sessionRecorderEventTask?.value
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
        case let .playCurrentStepSound(applyRecognitionSuppress):
            playCurrentStepSound(applyRecognitionSuppress: applyRecognitionSuppress)
        case .stopTransientWork:
            stopManualReplayTask()
            playbackControlService?.stopTransientWork()
        case .stopAudioRecognition:
            stopAudioRecognition()
        case .stopPracticeInput:
            stopPracticeInput()
        }
    }
}
