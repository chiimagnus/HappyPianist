import Foundation
import Observation
import os
import simd

@MainActor
@Observable
final class PracticeSessionViewModel {
    private let decisionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioDecision"
    )
    let timingLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3PracticeTiming"
    )

    static func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    enum VisualFeedbackState: Equatable {
        case none
        case correct
        case wrong
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
    private(set) var pressedNotes: Set<Int> = []
    var feedbackState: VisualFeedbackState = .none
    var isSustainPedalDown = false
    private(set) var audioRecognitionErrorMessage: String?
    private(set) var audioPlaybackErrorMessage: String?
    var autoplayErrorMessage: String?
    var audioErrorMessage: String? {
        audioRecognitionErrorMessage ?? audioPlaybackErrorMessage
    }

    private(set) var audioRecognitionStatus: PracticeAudioRecognitionStatus = .idle
    private(set) var audioRecognitionDebugSnapshot: PracticeAudioRecognitionDebugSnapshot = .empty
    private(set) var handGateState = HandGateState(
        isNearKeyboard: false,
        hasDownwardMotion: false,
        exactPressedNotes: [],
        confidenceBoost: 0
    )
    var noteMatchTolerance: Int = 1

    private let pressDetectionService: PressDetectionServiceProtocol
    let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    let sleeper: SleeperProtocol
    let timingClock: PracticeTimingClockProtocol
    private let noteAudioPlayer: PracticeNoteAudioPlayerProtocol?
    let noteOutput: PracticeMIDINoteOutputProtocol?
    private let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    private let audioStepAttemptAccumulator: AudioStepAttemptAccumulator
    private let handPianoActivityGate: HandPianoActivityGate
    private let manualAdvanceModeProvider: () -> ManualAdvanceMode
    var feedbackResetTask: Task<Void, Never>?
    var autoplayTask: Task<Void, Never>?
    var autoplayTaskGeneration = 0
    private var audioRecognitionEventsTask: Task<Void, Never>?
    private var audioRecognitionStatusTask: Task<Void, Never>?
    private var audioRecognitionDebugTask: Task<Void, Never>?
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
    var currentAutoplayEventIndex = 0
    var activeAutoplayMIDINotes: Set<Int> = []
    var pendingPedalReleaseOffTickByMIDI: [Int: Int] = [:]
    private(set) var highlightGuides: [PianoHighlightGuide] = []
    var currentHighlightGuideIndex: Int?
    var manualHighlightTransitionTask: Task<Void, Never>?
    var audioRecognitionGeneration = 0
    var isAudioRecognitionRunning = false
    private var audioRecognitionSuppressUntil: Date?
    private let audioRecognitionSuppressDuration: TimeInterval = 0.6
    private let audioRecognitionEnabledSnapshot = MusicXMLRealisticPlaybackDefaults.audioRecognitionEnabled
    private var practiceAudioRecognitionDetectorModeSnapshot: PracticeAudioRecognitionDetectorMode = .harmonicTemplate
    private var harmonicTemplateTuningProfileSnapshot: HarmonicTemplateTuningProfile = .lowLatencyDefault

    init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        timingClock: PracticeTimingClockProtocol? = nil,
        noteAudioPlayer: PracticeNoteAudioPlayerProtocol?,
        noteOutput: PracticeMIDINoteOutputProtocol? = nil,
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
        self.timingClock = timingClock ?? ContinuousPracticeTimingClock()
        self.noteAudioPlayer = noteAudioPlayer
        self.noteOutput = noteOutput
        self.audioRecognitionService = audioRecognitionService
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator ?? AudioStepAttemptAccumulator()
        self.handPianoActivityGate = handPianoActivityGate ?? HandPianoActivityGate()
        self.manualAdvanceModeProvider = manualAdvanceModeProvider
        bindAudioRecognitionStreamsIfNeeded()
    }

    convenience init() {
        let player = SoundFontPracticeNoteAudioPlayer(soundFontResourceName: "SalC5Light2")
        self.init(
            pressDetectionService: PressDetectionService(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            noteAudioPlayer: player,
            noteOutput: player,
            audioRecognitionService: PracticeAudioRecognitionService()
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
        noteSpans: [MusicXMLNoteSpan] = [],
        highlightGuides: [PianoHighlightGuide] = [],
        measureSpans: [MusicXMLMeasureSpan] = []
    ) {
        if state == .completed, self.steps == steps, steps.isEmpty == false {
            return
        }

        let shouldResetProgress = self.steps != steps

        feedbackResetTask?.cancel()
        feedbackResetTask = nil
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
        resetAutoplayCursorForCurrentStep()

        if shouldResetProgress {
            currentStepIndex = 0
            currentHighlightGuideIndex = nil
            pressedNotes.removeAll()
            feedbackState = .none
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

    func clearCalibration() {
        calibration = nil
        keyboardGeometry = nil
        pressedNotes.removeAll()
        handPianoActivityGate.reset()
        handGateState = HandGateState(
            isNearKeyboard: false,
            hasDownwardMotion: false,
            exactPressedNotes: [],
            confidenceBoost: 0
        )
    }

    func resetSession() {
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
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
        feedbackState = .none
        isSustainPedalDown = false
        audioRecognitionErrorMessage = nil
        audioPlaybackErrorMessage = nil
        autoplayErrorMessage = nil
        currentStepIndex = 0
        state = .idle
        autoplayTimeline = .empty
        resetAutoplayCursorForCurrentStep()
        activeAutoplayMIDINotes = []
        pendingPedalReleaseOffTickByMIDI = [:]
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
        stopManualReplayTask()
        stopAutoplayTask()
        stopAutoplayAudio()
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
            try noteAudioPlayer?.play(midiNotes: uniqueMIDINotes(in: currentStep))
        } catch {
            recordPlaybackError(error)
        }
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            stopManualReplayTask()
            do {
                try (noteOutput as? PracticeMIDINoteOutputWarmupProtocol)?.warmUp()
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

    func handleFingerTipPositions(_ fingerTips: [String: SIMD3<Float>], at timestamp: Date = .now) -> Set<Int> {
        guard let keyboardGeometry else { return [] }
        let detected = pressDetectionService.detectPressedNotes(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp
        )
        if detected.isEmpty == false {
            pressedNotes = detected
            handGateState = handPianoActivityGate.evaluate(
                fingerTips: fingerTips,
                keyboardGeometry: keyboardGeometry,
                exactPressedNotes: detected
            )
            if autoplayState == .off, isManualReplayPlaying == false, let currentStep {
                let expected = uniqueMIDINotes(in: currentStep)
                let isMatched = chordAttemptAccumulator.register(
                    pressedNotes: detected,
                    expectedNotes: expected,
                    tolerance: noteMatchTolerance,
                    at: timestamp
                )
                if isMatched {
                    setFeedback(.correct)
                    if autoplayState == .off {
                        advanceToNextStep()
                    }
                } else {
                    let unrelatedPressDetected = detected.contains { pressed in
                        expected.contains(where: { abs($0 - pressed) <= noteMatchTolerance }) == false
                    }
                    if unrelatedPressDetected {
                        setFeedback(.wrong)
                    }
                }
            }
        } else {
            handGateState = handPianoActivityGate.evaluate(
                fingerTips: fingerTips,
                keyboardGeometry: keyboardGeometry,
                exactPressedNotes: []
            )
        }
        return detected
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

    private func advanceToNextStep() {
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
        let previousTick = steps.indices.contains(currentStepIndex) ? steps[currentStepIndex].tick : steps[nextStepIndex].tick
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

    private func uniqueMIDINotes(in step: PracticeStep) -> [Int] {
        Set(step.notes.map(\.midiNote)).sorted()
    }

    func recordPlaybackError(_ error: Error) {
        guard audioPlaybackErrorMessage == nil else { return }
        audioPlaybackErrorMessage = audioErrorText(for: error)
    }

    private func recordAudioRecognitionError(_ error: Error) {
        guard audioRecognitionErrorMessage == nil else { return }
        audioRecognitionErrorMessage = audioErrorText(for: error)
    }

    private func audioErrorText(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription,
           description.isEmpty == false
        {
            return description
        }
        return String(describing: error)
    }

    private func setFeedback(_ state: VisualFeedbackState, duration: TimeInterval = 0.25) {
        feedbackState = state
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await sleeper.sleep(for: .seconds(duration))
            guard Task.isCancelled == false else { return }
            feedbackState = .none
        }
    }

    private func bindAudioRecognitionStreamsIfNeeded() {
        guard let audioRecognitionService else { return }
        guard audioRecognitionEventsTask == nil else { return }

        audioRecognitionEventsTask = Task { [weak self] in
            for await event in audioRecognitionService.events {
                await MainActor.run {
                    self?.handleAudioRecognitionEvent(event)
                }
            }
        }

        audioRecognitionStatusTask = Task { [weak self] in
            for await status in audioRecognitionService.statusUpdates {
                await MainActor.run {
                    self?.audioRecognitionStatus = status
                    if case .permissionDenied = status {
                        self?.audioRecognitionErrorMessage = "未授予麦克风权限"
                    }
                    if case let .engineFailed(reason) = status {
                        self?.audioRecognitionErrorMessage = reason
                    }
                }
            }
        }

        audioRecognitionDebugTask = Task { [weak self] in
            for await snapshot in audioRecognitionService.debugSnapshots {
                await MainActor.run {
                    self?.audioRecognitionDebugSnapshot = snapshot
                }
            }
        }
    }

    func refreshAudioRecognitionForCurrentState() {
        guard let audioRecognitionService else { return }
        guard isPracticeAudioRecognitionEnabled else {
            stopAudioRecognition()
            return
        }
        guard autoplayState == .off else {
            stopAudioRecognition()
            return
        }
        guard isManualReplayPlaying == false else {
            stopAudioRecognition()
            return
        }
        guard case .guiding = state, let currentStep else {
            stopAudioRecognition()
            return
        }

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let wrongMIDINotes = makeWrongCandidateMIDINotes(expectedMIDINotes)
        audioRecognitionService.configureDetectorMode(
            practiceAudioRecognitionDetectorModeSnapshot,
            profile: harmonicTemplateTuningProfileSnapshot
        )
        audioStepAttemptAccumulator.setMode(.lowLatency)
        audioRecognitionGeneration += 1
        audioStepAttemptAccumulator.resetForNewStep(generation: audioRecognitionGeneration)

        if isAudioRecognitionRunning {
            audioRecognitionService.updateExpectedNotes(
                expectedMIDINotes,
                wrongCandidateMIDINotes: wrongMIDINotes,
                generation: audioRecognitionGeneration
            )
            applyPendingAudioRecognitionSuppressIfNeeded(generation: audioRecognitionGeneration)
            decisionLogger.debug("audio generation update=\(self.audioRecognitionGeneration, privacy: .public)")
            return
        }

        isAudioRecognitionRunning = true
        let startGeneration = audioRecognitionGeneration
        let startExpectedMIDINotes = expectedMIDINotes
        let startWrongMIDINotes = wrongMIDINotes
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await audioRecognitionService.start(
                    expectedMIDINotes: startExpectedMIDINotes,
                    wrongCandidateMIDINotes: startWrongMIDINotes,
                    generation: startGeneration,
                    suppressUntil: audioRecognitionSuppressUntil.flatMap { $0 > Date() ? $0 : nil }
                )
                guard audioRecognitionGeneration == startGeneration,
                      autoplayState == .off,
                      isPracticeAudioRecognitionEnabled,
                      case .guiding = state
                else {
                    stopAudioRecognition()
                    return
                }
                applyPendingAudioRecognitionSuppressIfNeeded(generation: startGeneration)
                decisionLogger.info("audio service started generation=\(startGeneration, privacy: .public)")
            } catch {
                isAudioRecognitionRunning = false
                decisionLogger.error("audio service failed start generation=\(startGeneration, privacy: .public)")
                recordAudioRecognitionError(error)
            }
        }
    }

    func refreshAudioRecognitionFromSettings() {
        practiceAudioRecognitionDetectorModeSnapshot = Self.readPracticeAudioRecognitionDetectorMode()
        harmonicTemplateTuningProfileSnapshot = Self.profile(for: practiceAudioRecognitionDetectorModeSnapshot)
        audioRecognitionService?.configureDetectorMode(
            practiceAudioRecognitionDetectorModeSnapshot,
            profile: harmonicTemplateTuningProfileSnapshot
        )
        refreshAudioRecognitionForCurrentState()
    }

    func stopAudioRecognition() {
        guard let audioRecognitionService else { return }
        audioRecognitionGeneration += 1
        audioStepAttemptAccumulator.resetForNewStep(generation: audioRecognitionGeneration)
        audioRecognitionService.stop()
        isAudioRecognitionRunning = false
        audioRecognitionStatus = .stopped
        decisionLogger.debug("audio service stopped by lifecycle")
    }

    private func prepareAudioRecognitionSuppressWindowForPlayback() -> Date {
        let suppressUntil = Date().addingTimeInterval(audioRecognitionSuppressDuration)
        audioRecognitionSuppressUntil = suppressUntil
        audioRecognitionService?.suppressRecognition(
            until: suppressUntil,
            generation: audioRecognitionGeneration
        )
        return suppressUntil
    }

    private func applyPendingAudioRecognitionSuppressIfNeeded(generation: Int) {
        guard let audioRecognitionService else { return }
        guard let audioRecognitionSuppressUntil else { return }
        guard audioRecognitionSuppressUntil > Date() else { return }
        audioRecognitionService.suppressRecognition(
            until: audioRecognitionSuppressUntil,
            generation: generation
        )
    }

    private func handleAudioRecognitionEvent(_ event: DetectedNoteEvent) {
        guard isPracticeAudioRecognitionEnabled else { return }
        guard autoplayState == .off else { return }
        guard isManualReplayPlaying == false else { return }
        guard event.generation == audioRecognitionGeneration else { return }
        if let audioRecognitionSuppressUntil, event.timestamp <= audioRecognitionSuppressUntil {
            decisionLogger.debug("audio event suppressed generation=\(event.generation, privacy: .public)")
            return
        }
        guard let currentStep else { return }

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let wrongMIDINotes = Set(makeWrongCandidateMIDINotes(expectedMIDINotes))

        audioStepAttemptAccumulator.register(event: event)
        let matchResult = audioStepAttemptAccumulator.evaluate(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongMIDINotes,
            generation: audioRecognitionGeneration,
            at: event.timestamp,
            handGateBoost: handGateState.isNearKeyboard || handGateState.hasDownwardMotion
        )

        switch matchResult {
            case .matched:
                audioStepAttemptAccumulator.markMatchedAndRequireRearm(
                    expectedMIDINotes: expectedMIDINotes,
                    at: event.timestamp
                )
                setFeedback(.correct)
                advanceToNextStep()
                decisionLogger.debug("audio matched advanced generation=\(event.generation, privacy: .public)")
            case .wrong:
                setFeedback(.wrong)
                decisionLogger.debug("audio wrong feedback generation=\(event.generation, privacy: .public)")
            case .insufficient:
                break
        }
    }

    private func makeWrongCandidateMIDINotes(_ expectedMIDINotes: [Int]) -> [Int] {
        var result: Set<Int> = []
        for note in expectedMIDINotes {
            result.insert(note - 2)
            result.insert(note - 1)
            result.insert(note + 1)
            result.insert(note + 2)
        }
        result.subtract(expectedMIDINotes)
        return result.sorted()
    }

    private var isPracticeAudioRecognitionEnabled: Bool {
        audioRecognitionEnabledSnapshot
    }


    var audioRecognitionGenerationForTesting: Int {
        audioRecognitionGeneration
    }

    var audioRecognitionSuppressRemainingSeconds: TimeInterval {
        guard let audioRecognitionSuppressUntil else { return 0 }
        return max(0, audioRecognitionSuppressUntil.timeIntervalSinceNow)
    }

    private static func readPracticeAudioRecognitionDetectorMode() -> PracticeAudioRecognitionDetectorMode {
        if let rawValue = UserDefaults.standard.string(forKey: "practiceStep3AudioRecognitionMode"),
           let mode = PracticeAudioRecognitionDetectorMode(rawValue: rawValue)
        {
            return mode
        }
        return .harmonicTemplate
    }

    private static func profile(for _: PracticeAudioRecognitionDetectorMode) -> HarmonicTemplateTuningProfile {
        .lowLatencyDefault
    }
}
