import Foundation
import Observation
import os

@dynamicMemberLookup
@MainActor
@Observable
final class PracticeSessionViewModel: PracticeSessionLifecycleProtocol, PracticeSessionEffectHandling {
    nonisolated static let practiceHandSeparatedStepMatchingEnabledKey = "practiceHandSeparatedStepMatchingEnabled"

    let stateStore: PracticeSessionStateStore
    let stepNavigator: PracticeStepNavigator

    let pressDetectionService: PressDetectionServiceProtocol
    let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    let sleeper: SleeperProtocol
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    let playbackSequenceBuilder: PlaybackSequenceBuilder
    let keyContactDetectionService: KeyContactDetectionService
    let realPianoContactDetectionService: RealPianoContactDetectionService
    let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    let practiceInputEventSource: PracticeInputEventSourceProtocol?
    let audioStepAttemptAccumulator: AudioStepAttemptAccumulator
    let midiPracticeStepMatcher: MIDIPracticeStepMatcher

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
        UserDefaults.standard.bool(forKey: Self.practiceHandSeparatedStepMatchingEnabledKey)
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
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        practiceInputEventSource: PracticeInputEventSourceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator,
        handPianoActivityGate: HandPianoActivityGate,
        manualAdvanceModeProvider: @escaping () -> ManualAdvanceMode = {
            ManualAdvanceMode.storageValue(from: UserDefaults.standard.string(forKey: "practiceManualAdvanceMode"))
        }
    ) {
        stateStore = PracticeSessionStateStore()
        stepNavigator = PracticeStepNavigator()

        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService
        playbackSequenceBuilder = PlaybackSequenceBuilder()
        keyContactDetectionService = KeyContactDetectionService()
        realPianoContactDetectionService = RealPianoContactDetectionService()
        self.audioRecognitionService = audioRecognitionService
        self.practiceInputEventSource = practiceInputEventSource
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator
        midiPracticeStepMatcher = MIDIPracticeStepMatcher()
        self.handPianoActivityGate = handPianoActivityGate
        self.manualAdvanceModeProvider = manualAdvanceModeProvider

        practiceMIDIInputCoordinator = PracticeMIDIInputCoordinator(
            practiceInputEventSource: practiceInputEventSource,
            matcher: midiPracticeStepMatcher,
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
            playbackSequenceBuilder: playbackSequenceBuilder,
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
            playbackSequenceBuilder: playbackSequenceBuilder,
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
            detector: keyContactDetectionService,
            sequencerPlaybackService: sequencerPlaybackService,
            stateStore: stateStore,
            handGateController: handGateController
        )
    }

    @available(*, deprecated, message: "Inject dependencies via AppServices/CompositionRoot.")
    convenience init() {
        self.init(
            pressDetectionService: PressDetectionService(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            sequencerPlaybackService: AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2"),
            audioRecognitionService: nil,
            practiceInputEventSource: nil,
            audioStepAttemptAccumulator: AudioStepAttemptAccumulator(),
            handPianoActivityGate: HandPianoActivityGate()
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
