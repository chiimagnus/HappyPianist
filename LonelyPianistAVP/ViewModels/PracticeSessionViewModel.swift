import Foundation
import Observation
import os
import simd

@MainActor
@Observable
final class PracticeSessionViewModel {
    let decisionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioDecision"
    )

    static func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    enum PracticeState: Equatable {
        case idle
        case ready
        case guiding(stepIndex: Int)
        case completed
    }

    enum AutoplayState: Equatable {
        case off
        case playing
    }

    var state: PracticeState = .idle
    private(set) var steps: [PracticeStep] = []
    var autoplayState: AutoplayState = .off
    private(set) var calibration: PianoCalibration?
    private(set) var keyboardGeometry: PianoKeyboardGeometry?
    var pressedNotes: Set<Int> = []
    private(set) var latestNoteOnMIDINotes: Set<Int> = []
    var isSustainPedalDown = false
    var audioRecognitionErrorMessage: String?
    private(set) var audioPlaybackErrorMessage: String?
    var autoplayErrorMessage: String?
    var audioErrorMessage: String? {
        audioRecognitionErrorMessage ?? audioPlaybackErrorMessage
    }

    var audioRecognitionStatus: PracticeAudioRecognitionStatus = .idle
    var audioRecognitionDebugSnapshot: PracticeAudioRecognitionDebugSnapshot = .empty
    var handGateState = HandGateState(
        isNearKeyboard: false,
        hasDownwardMotion: false,
        exactPressedNotes: [],
        confidenceBoost: 0
    )
    var noteMatchTolerance: Int = 1

    let pressDetectionService: PressDetectionServiceProtocol
    let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    let sleeper: SleeperProtocol
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    let keyContactDetectionService = KeyContactDetectionService()
    let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    let audioStepAttemptAccumulator: AudioStepAttemptAccumulator
    let handPianoActivityGate: HandPianoActivityGate
    private let manualAdvanceModeProvider: () -> ManualAdvanceMode
    var autoplayTask: Task<Void, Never>?
    var autoplayTaskGeneration = 0
    var audioRecognitionEventsTask: Task<Void, Never>?
    var audioRecognitionStatusTask: Task<Void, Never>?
    var audioRecognitionDebugTask: Task<Void, Never>?
    private(set) var tempoMap = MusicXMLTempoMap(tempoEvents: [])
    private var measureSpans: [MusicXMLMeasureSpan] = []
    var manualReplayTask: Task<Void, Never>?
    var manualReplayGeneration = 0
    var isManualReplayPlaying = false
    var shouldResumeAudioRecognitionAfterManualReplay = false
    var pedalTimeline: MusicXMLPedalTimeline?
    var fermataTimeline: MusicXMLFermataTimeline?
    private var attributeTimeline: MusicXMLAttributeTimeline?
    private var slurTimeline: MusicXMLSlurTimeline?
    var autoplayTimeline: AutoplayPerformanceTimeline = .empty
    private(set) var highlightGuides: [PianoHighlightGuide] = []
    var currentHighlightGuideIndex: Int?
    var manualHighlightTransitionTask: Task<Void, Never>?
    var audioRecognitionGeneration = 0
    var isAudioRecognitionRunning = false
    var audioRecognitionSuppressUntil: Date?
    let audioRecognitionSuppressDuration: TimeInterval = 0.6
    let audioRecognitionEnabledSnapshot = MusicXMLRealisticPlaybackDefaults.audioRecognitionEnabled
    var practiceAudioRecognitionDetectorModeSnapshot: PracticeAudioRecognitionDetectorMode = .harmonicTemplate
    var harmonicTemplateTuningProfileSnapshot: HarmonicTemplateTuningProfile = .lowLatencyDefault

    init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol? = nil,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator? = nil,
        handPianoActivityGate: HandPianoActivityGate? = nil,
        manualAdvanceModeProvider: @escaping () -> ManualAdvanceMode = {
            ManualAdvanceMode.storageValue(from: UserDefaults.standard.string(forKey: "practiceManualAdvanceMode"))
        }
    ) {
        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService ?? AVAudioSequencerPracticePlaybackService(
            soundFontResourceName: "SalC5Light2"
        )
        self.audioRecognitionService = audioRecognitionService
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator ?? AudioStepAttemptAccumulator()
        self.handPianoActivityGate = handPianoActivityGate ?? HandPianoActivityGate()
        self.manualAdvanceModeProvider = manualAdvanceModeProvider
        bindAudioRecognitionStreamsIfNeeded()
    }

    convenience init() {
        let playbackService = AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
#if targetEnvironment(simulator)
        let audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil
#else
        let audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = PracticeAudioRecognitionService()
#endif
        self.init(
            pressDetectionService: PressDetectionService(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            sequencerPlaybackService: playbackService,
            audioRecognitionService: audioRecognitionService
        )
    }

    var currentStepIndex: Int = 0 {
        didSet {
            if steps.isEmpty {
                state = .idle
            } else {
                state = .guiding(stepIndex: currentStepIndex)
            }
        }
    }

    var currentStep: PracticeStep? {
        guard state != .completed else { return nil }
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var currentPianoHighlightGuide: PianoHighlightGuide? {
        guard let currentHighlightGuideIndex else { return nil }
        guard highlightGuides.indices.contains(currentHighlightGuideIndex) else { return nil }
        return highlightGuides[currentHighlightGuideIndex]
    }

    var currentMusicXMLAttributeSummaryText: String? {
        guard let attributeTimeline else { return nil }
        guard let currentStep else { return nil }

        let tick = currentStep.tick

        var parts: [String] = []
        if let time = attributeTimeline.timeSignature(atTick: tick) {
            parts.append("\(time.beats)/\(time.beatType)")
        }
        if let key = attributeTimeline.keySignature(atTick: tick) {
            let fifths = key.fifths
            let token = fifths >= 0 ? "+\(fifths)" : "\(fifths)"
            parts.append("Key \(token)")
        }

        let rh = attributeTimeline.clef(atTick: tick, staffNumber: 1).flatMap { Self.clefToken(for: $0) }
        let lh = attributeTimeline.clef(atTick: tick, staffNumber: 2).flatMap { Self.clefToken(for: $0) }
        let clefTokens = [rh, lh].compactMap(\.self)
        if clefTokens.isEmpty == false {
            parts.append("Clef \(clefTokens.joined(separator: "/"))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func clefToken(for event: MusicXMLClefEvent) -> String? {
        guard let sign = event.signToken, sign.isEmpty == false else { return nil }
        switch sign.uppercased() {
            case "G":
                return "G"
            case "F":
                return "F"
            case "C":
                return "C"
            default:
                return sign
        }
    }

    var isMusicXMLSlurActive: Bool {
        guard let slurTimeline else { return false }
        guard let currentStep else { return false }
        return slurTimeline.isActive(atTick: currentStep.tick)
    }

    var manualAdvanceMode: ManualAdvanceMode {
        manualAdvanceModeProvider()
    }

    var canReplayCurrentManualUnit: Bool {
        currentStep != nil
    }

    private var manualAdvanceContext: ManualAdvanceContext {
        ManualAdvanceContext(
            currentStepIndex: currentStepIndex,
            steps: steps,
            measureSpans: measureSpans
        )
    }

    private var manualAdvanceStrategy: ManualAdvanceStrategyProtocol {
        switch manualAdvanceMode {
            case .step:
                StepManualAdvanceStrategy()
            case .measure:
                MeasureManualAdvanceStrategy()
        }
    }

    func setSteps(
        _ steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        pedalTimeline: MusicXMLPedalTimeline? = nil,
        fermataTimeline: MusicXMLFermataTimeline? = nil,
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        slurTimeline: MusicXMLSlurTimeline? = nil,
        noteSpans _: [MusicXMLNoteSpan] = [],
        highlightGuides: [PianoHighlightGuide] = [],
        measureSpans: [MusicXMLMeasureSpan] = []
    ) {
        if state == .completed, self.steps == steps, steps.isEmpty == false {
            return
        }

        let shouldResetProgress = self.steps != steps
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        manualHighlightTransitionTask?.cancel()
        manualHighlightTransitionTask = nil
        chordAttemptAccumulator.reset()
        self.steps = steps
        self.tempoMap = tempoMap
        self.measureSpans = measureSpans
        self.pedalTimeline = pedalTimeline
        self.fermataTimeline = fermataTimeline
        self.attributeTimeline = attributeTimeline
        self.slurTimeline = slurTimeline
        self.highlightGuides = highlightGuides
        rebuildAutoplayTimeline()
        currentHighlightGuideIndex = nil

        if shouldResetProgress {
            currentStepIndex = 0
            currentHighlightGuideIndex = nil
            pressedNotes.removeAll()
        }

        let tick = steps.indices.contains(currentStepIndex) ? steps[currentStepIndex].tick : 0
        isSustainPedalDown = pedalTimeline?.isDown(atTick: tick) ?? false

        if steps.isEmpty {
            state = .idle
        } else if state != .completed {
            state = .ready
        }

        refreshAudioRecognitionForCurrentState()
    }

    func applyKeyboardGeometry(_ keyboardGeometry: PianoKeyboardGeometry, calibration: PianoCalibration) {
        self.calibration = calibration
        self.keyboardGeometry = keyboardGeometry
        if steps.isEmpty == false, state != .completed, state != .guiding(stepIndex: currentStepIndex) {
            state = .ready
        }
    }

    func applyVirtualKeyboardGeometry(_ keyboardGeometry: PianoKeyboardGeometry) {
        self.keyboardGeometry = keyboardGeometry
        if steps.isEmpty == false, state != .completed, state != .guiding(stepIndex: currentStepIndex) {
            state = .ready
        }
    }

    func updateLatestNoteOnMIDINotes(_ midiNotes: Set<Int>) {
        latestNoteOnMIDINotes = midiNotes
    }

    func aiPerformanceTickRange(maxMeasures: Int = 2) -> (startTick: Int, endTick: Int)? {
        guard let currentStep else { return nil }
        return AIPerformanceClipSelector().tickRange(
            currentTick: currentStep.tick,
            measureSpans: measureSpans,
            maxMeasures: maxMeasures
        )
    }

    func clearCalibration() {
        calibration = nil
        keyboardGeometry = nil
        pressedNotes.removeAll()
        latestNoteOnMIDINotes.removeAll()
        handPianoActivityGate.reset()
        handGateState = HandGateState(
            isNearKeyboard: false,
            hasDownwardMotion: false,
            exactPressedNotes: [],
            confidenceBoost: 0
        )
    }

    func resetSession() {
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        chordAttemptAccumulator.reset()
        steps = []
        tempoMap = MusicXMLTempoMap(tempoEvents: [])
        measureSpans = []
        pedalTimeline = nil
        fermataTimeline = nil
        attributeTimeline = nil
        slurTimeline = nil
        highlightGuides = []
        currentHighlightGuideIndex = nil
        manualHighlightTransitionTask?.cancel()
        manualHighlightTransitionTask = nil
        calibration = nil
        keyboardGeometry = nil
        pressedNotes.removeAll()
        latestNoteOnMIDINotes.removeAll()
        keyContactDetectionService.reset()
        isSustainPedalDown = false
        audioRecognitionErrorMessage = nil
        audioPlaybackErrorMessage = nil
        autoplayErrorMessage = nil
        currentStepIndex = 0
        state = .idle
        autoplayTimeline = .empty
        handPianoActivityGate.reset()
        handGateState = HandGateState(
            isNearKeyboard: false,
            hasDownwardMotion: false,
            exactPressedNotes: [],
            confidenceBoost: 0
        )
    }

    func clearAudioError() {
        audioRecognitionErrorMessage = nil
        audioPlaybackErrorMessage = nil
    }

    func stopVirtualPianoInput() {
        sequencerPlaybackService.stopAllLiveNotes()
        keyContactDetectionService.reset()
        pressedNotes.removeAll()
        latestNoteOnMIDINotes.removeAll()
    }

    func clearAutoplayError() {
        autoplayErrorMessage = nil
    }

    func startGuidingIfReady() {
        guard state == .ready, steps.isEmpty == false else { return }
        currentStepIndex = 0
        setCurrentHighlightGuideForStepIndex(currentStepIndex)
        state = .guiding(stepIndex: currentStepIndex)
        if autoplayState == .playing {
            refreshAudioRecognitionForCurrentState()
        } else {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            refreshAudioRecognitionForCurrentState()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }
        startAutoplayTaskIfNeeded()
    }

    func skip() {
        if state == .ready {
            startGuidingIfReady()
            return
        }
        stopManualReplayTask()
        stopAutoplayTask()
        if autoplayState == .playing || isManualReplayPlaying {
            stopAutoplayAudio()
        }
        advanceToNextManualUnit()
        startAutoplayTaskIfNeeded()
    }

    func replayCurrentUnit() {
        guard autoplayState == .off else { return }
        guard let plan = manualAdvanceStrategy.replayPlan(in: manualAdvanceContext) else { return }
        startManualReplay(with: plan)
    }

    func playCurrentStepSound() {
        playCurrentStepSound(applyRecognitionSuppress: true)
    }

    func playCurrentStepSound(applyRecognitionSuppress: Bool) {
        guard let currentStep else { return }
        guard audioPlaybackErrorMessage == nil else { return }
        if applyRecognitionSuppress {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
        }

        do {
            try sequencerPlaybackService.playOneShot(
                midiNotes: uniqueMIDINotes(in: currentStep),
                durationSeconds: 0.35
            )
        } catch {
            recordPlaybackError(error)
        }
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            stopManualReplayTask()
            stopVirtualPianoInput()
            do {
                try sequencerPlaybackService.warmUp()
            } catch {
                recordPlaybackError(error)
            }
            autoplayState = .playing
            let tick = currentStep?.tick ?? 0
            isSustainPedalDown = pedalTimeline?.isDown(atTick: tick) ?? false
            autoplayErrorMessage = nil
            startAutoplayTaskIfNeeded()
        } else {
            autoplayState = .off
            stopAutoplayTask()
            stopAutoplayAudio()
        }
        refreshAudioRecognitionForCurrentState()
    }

    private func advanceToNextManualUnit() {
        guard steps.isEmpty == false else {
            state = .idle
            return
        }
        guard let nextIndex = manualAdvanceStrategy.nextStepIndex(in: manualAdvanceContext) else {
            completeManualAdvance()
            return
        }
        moveToStep(nextIndex, shouldPlaySound: autoplayState == .off)
    }

    func advanceToNextStep() {
        guard steps.isEmpty == false else {
            state = .idle
            return
        }
        chordAttemptAccumulator.reset()
        if currentStepIndex + 1 < steps.count {
            let previousTick = steps[currentStepIndex].tick
            currentStepIndex += 1
            state = .guiding(stepIndex: currentStepIndex)
            updateHighlightGuideAfterStepAdvance(previousTick: previousTick, nextStepIndex: currentStepIndex)
            if autoplayState == .playing {
                refreshAudioRecognitionForCurrentState()
            } else {
                _ = prepareAudioRecognitionSuppressWindowForPlayback()
                refreshAudioRecognitionForCurrentState()
                playCurrentStepSound(applyRecognitionSuppress: false)
            }
        } else {
            currentStepIndex = steps.count
            currentHighlightGuideIndex = nil
            pressedNotes.removeAll()
            state = .completed
            stopAutoplayTask()
            stopAutoplayAudio()
            stopAudioRecognition()
        }
    }

    func moveToStep(_ nextStepIndex: Int, shouldPlaySound: Bool) {
        guard steps.indices.contains(nextStepIndex) else {
            completeManualAdvance()
            return
        }
        let previousTick = steps.indices.contains(currentStepIndex) ? steps[currentStepIndex]
            .tick : steps[nextStepIndex].tick
        chordAttemptAccumulator.reset()
        currentStepIndex = nextStepIndex
        state = .guiding(stepIndex: nextStepIndex)
        updateHighlightGuideAfterStepAdvance(previousTick: previousTick, nextStepIndex: nextStepIndex)
        refreshAudioRecognitionForCurrentState()
        if shouldPlaySound {
            _ = prepareAudioRecognitionSuppressWindowForPlayback()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }
    }

    private func completeManualAdvance() {
        currentStepIndex = steps.count
        currentHighlightGuideIndex = nil
        pressedNotes.removeAll()
        state = .completed
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
    }

    func uniqueMIDINotes(in step: PracticeStep) -> [Int] {
        Set(step.notes.map(\.midiNote)).sorted()
    }

    func recordPlaybackError(_ error: Error) {
        guard audioPlaybackErrorMessage == nil else { return }
        audioPlaybackErrorMessage = audioErrorText(for: error)
    }

    func audioErrorText(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription,
           description.isEmpty == false
        {
            return description
        }
        return String(describing: error)
    }
}
