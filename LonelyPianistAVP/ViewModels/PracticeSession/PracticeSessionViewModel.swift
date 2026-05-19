import Foundation
import Observation
import os

@dynamicMemberLookup
@MainActor
@Observable
final class PracticeSessionViewModel: PracticeSessionLifecycleProtocol, PracticeSessionEffectHandlerProtocol {
    nonisolated static let practiceHandSeparatedStepMatchingEnabledKey = PracticeSessionSettingsKeys.handSeparatedStepMatchingEnabled

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

    var practiceMIDIInputCoordinator: PracticeMIDIInputCoordinator?
    var audioRecognitionCoordinator: PracticeAudioRecognitionCoordinator?
    var playbackCoordinator: PracticePlaybackCoordinator?
    var manualReplayCoordinator: PracticeManualReplayCoordinator?
    var highlightGuideController: PracticeHighlightGuideController?
    var handGateController: PracticeHandGateController?
    var virtualPianoInputController: VirtualPianoInputController?

    let handPianoActivityGate: HandPianoActivityGate
    let manualAdvanceModeProvider: () -> ManualAdvanceMode

    let audioRecognitionSuppressDuration: TimeInterval = 0.6
    let audioRecognitionEnabledSnapshot = MusicXMLRealisticPlaybackDefaults.audioRecognitionEnabled
    let autoplayTimingLeadInSeconds: TimeInterval = 0.05

    private var hasShutdown = false

    var isHandSeparatedStepMatchingEnabled: Bool {
        settingsProvider.isHandSeparatedStepMatchingEnabled
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
        manualAdvanceModeProvider: (() -> ManualAdvanceMode)? = nil
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
        self.manualAdvanceModeProvider = manualAdvanceModeProvider ?? { resolvedSettingsProvider.manualAdvanceMode }

        practiceMIDIInputCoordinator = PracticeMIDIInputCoordinator(
            practiceInputEventSource: practiceInputEventSource,
            matcher: self.midiPracticeStepMatcher,
            stateStore: stateStore,
            effectHandler: self,
            consumeEvents: true
        )
        audioRecognitionCoordinator = PracticeAudioRecognitionCoordinator(
            service: audioRecognitionService,
            accumulator: audioStepAttemptAccumulator,
            stateStore: stateStore,
            effectHandler: self,
            consumeStreams: true
        )

        playbackCoordinator = PracticePlaybackCoordinator(
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

        manualReplayCoordinator = PracticeManualReplayCoordinator(
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
        playbackCoordinator?.shutdown()
        handle(effect: .stopAudioRecognition)
        handle(effect: .stopPracticeInput)

        audioRecognitionCoordinator?.shutdown()
        practiceMIDIInputCoordinator?.shutdown()
        highlightGuideController?.shutdown()
        manualReplayCoordinator?.shutdown()
        handGateController?.shutdown()
        virtualPianoInputController?.shutdown()
    }

    func handle(effect: PracticeSessionEffect) {
        switch effect {
        case .advanceToNextStep:
            advanceToNextStep()
        case .refreshPracticeInput:
            refreshPracticeInputForCurrentState()
        case .refreshAudioRecognition:
            refreshAudioRecognitionForCurrentState()
        case let .playCurrentStepSound(applyRecognitionSuppress):
            playCurrentStepSound(applyRecognitionSuppress: applyRecognitionSuppress)
        case .stopTransientWork:
            stopManualReplayTask()
            playbackCoordinator?.stopTransientWork()
        case .stopAudioRecognition:
            stopAudioRecognition()
        case .stopPracticeInput:
            stopPracticeInput()
        }
    }
}
