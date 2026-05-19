import Foundation
import Observation
import os
import simd

@MainActor
@Observable
final class PracticeSessionViewModel: PracticeSessionLifecycleProtocol {
    nonisolated static let practiceHandSeparatedStepMatchingEnabledKey = "practiceHandSeparatedStepMatchingEnabled"

    let decisionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioDecision"
    )

    private let stateStore = PracticeSessionStateStore()

    var isHandSeparatedStepMatchingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.practiceHandSeparatedStepMatchingEnabledKey)
    }

    static func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    typealias PracticeState = PracticeSessionState

    typealias AutoplayState = PracticeSessionAutoplayState

    var state: PracticeState {
        get { stateStore.state }
        set { stateStore.state = newValue }
    }

    private(set) var steps: [PracticeStep] {
        get { stateStore.steps }
        set { stateStore.steps = newValue }
    }

    var autoplayState: AutoplayState {
        get { stateStore.autoplayState }
        set { stateStore.autoplayState = newValue }
    }

    private(set) var calibration: PianoCalibration? {
        get { stateStore.calibration }
        set { stateStore.calibration = newValue }
    }

    private(set) var keyboardGeometry: PianoKeyboardGeometry? {
        get { stateStore.keyboardGeometry }
        set { stateStore.keyboardGeometry = newValue }
    }

    var pressedNotes: Set<Int> {
        get { stateStore.pressedNotes }
        set { stateStore.pressedNotes = newValue }
    }

    private(set) var latestNoteOnMIDINotes: Set<Int> {
        get { stateStore.latestNoteOnMIDINotes }
        set { stateStore.latestNoteOnMIDINotes = newValue }
    }

    var latestKeyContactResult: KeyContactResult {
        get { stateStore.latestKeyContactResult }
        set { stateStore.latestKeyContactResult = newValue }
    }

    var isSustainPedalDown: Bool {
        get { stateStore.isSustainPedalDown }
        set { stateStore.isSustainPedalDown = newValue }
    }

    var audioRecognitionErrorMessage: String? {
        get { stateStore.audioRecognitionErrorMessage }
        set { stateStore.audioRecognitionErrorMessage = newValue }
    }

    private(set) var audioPlaybackErrorMessage: String? {
        get { stateStore.audioPlaybackErrorMessage }
        set { stateStore.audioPlaybackErrorMessage = newValue }
    }

    var autoplayErrorMessage: String? {
        get { stateStore.autoplayErrorMessage }
        set { stateStore.autoplayErrorMessage = newValue }
    }
    var audioErrorMessage: String? {
        audioRecognitionErrorMessage ?? audioPlaybackErrorMessage
    }

    var audioRecognitionStatus: PracticeAudioRecognitionStatus {
        get { stateStore.audioRecognitionStatus }
        set { stateStore.audioRecognitionStatus = newValue }
    }

    var audioRecognitionDebugSnapshot: PracticeAudioRecognitionDebugSnapshot {
        get { stateStore.audioRecognitionDebugSnapshot }
        set { stateStore.audioRecognitionDebugSnapshot = newValue }
    }

    var handGateState: HandGateState {
        get { stateStore.handGateState }
        set { stateStore.handGateState = newValue }
    }

    var noteMatchTolerance: Int {
        get { stateStore.noteMatchTolerance }
        set { stateStore.noteMatchTolerance = newValue }
    }

    let pressDetectionService: PressDetectionServiceProtocol
    let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    let sleeper: SleeperProtocol
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    let keyContactDetectionService = KeyContactDetectionService()
    let realPianoContactDetectionService = RealPianoContactDetectionService()
    let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    let practiceInputEventSource: PracticeInputEventSourceProtocol?
    let audioStepAttemptAccumulator: AudioStepAttemptAccumulator
    let midiPracticeStepMatcher = MIDIPracticeStepMatcher()
    let handPianoActivityGate: HandPianoActivityGate
    private let manualAdvanceModeProvider: () -> ManualAdvanceMode
    var autoplayTask: Task<Void, Never>?
    var autoplayTaskGeneration = 0
    var audioRecognitionEventsTask: Task<Void, Never>?
    var audioRecognitionStatusTask: Task<Void, Never>?
    var audioRecognitionDebugTask: Task<Void, Never>?
    var practiceInputMIDI1EventsTask: Task<Void, Never>?
    var practiceInputMIDI2EventsTask: Task<Void, Never>?
    private var hasShutdown = false
    private(set) var tempoMap: MusicXMLTempoMap {
        get { stateStore.tempoMap }
        set { stateStore.tempoMap = newValue }
    }

    private var measureSpans: [MusicXMLMeasureSpan] {
        get { stateStore.measureSpans }
        set { stateStore.measureSpans = newValue }
    }
    var manualReplayTask: Task<Void, Never>?
    var manualReplayGeneration: Int {
        get { stateStore.manualReplayGeneration }
        set { stateStore.manualReplayGeneration = newValue }
    }

    var isManualReplayPlaying: Bool {
        get { stateStore.isManualReplayPlaying }
        set { stateStore.isManualReplayPlaying = newValue }
    }

    var shouldResumeAudioRecognitionAfterManualReplay: Bool {
        get { stateStore.shouldResumeAudioRecognitionAfterManualReplay }
        set { stateStore.shouldResumeAudioRecognitionAfterManualReplay = newValue }
    }

    var pedalTimeline: MusicXMLPedalTimeline? {
        get { stateStore.pedalTimeline }
        set { stateStore.pedalTimeline = newValue }
    }

    var fermataTimeline: MusicXMLFermataTimeline? {
        get { stateStore.fermataTimeline }
        set { stateStore.fermataTimeline = newValue }
    }

    private var attributeTimeline: MusicXMLAttributeTimeline? {
        get { stateStore.attributeTimeline }
        set { stateStore.attributeTimeline = newValue }
    }

    private var slurTimeline: MusicXMLSlurTimeline? {
        get { stateStore.slurTimeline }
        set { stateStore.slurTimeline = newValue }
    }

    var autoplayTimeline: AutoplayPerformanceTimeline {
        get { stateStore.autoplayTimeline }
        set { stateStore.autoplayTimeline = newValue }
    }

    private(set) var highlightGuides: [PianoHighlightGuide] {
        get { stateStore.highlightGuides }
        set { stateStore.highlightGuides = newValue }
    }

    var currentHighlightGuideIndex: Int? {
        get { stateStore.currentHighlightGuideIndex }
        set { stateStore.currentHighlightGuideIndex = newValue }
    }

    var autoplayTimingBaseTick: Int? {
        get { stateStore.autoplayTimingBaseTick }
        set { stateStore.autoplayTimingBaseTick = newValue }
    }
    let autoplayTimingLeadInSeconds: TimeInterval = 0.05
    typealias NotationGuideScrollPoint = PracticeSessionNotationGuideScrollPoint

    var notationGuideScrollSchedule: [NotationGuideScrollPoint] {
        get { stateStore.notationGuideScrollSchedule }
        set { stateStore.notationGuideScrollSchedule = newValue }
    }

    var notationGuideScrollScheduleBaseTick: Int {
        get { stateStore.notationGuideScrollScheduleBaseTick }
        set { stateStore.notationGuideScrollScheduleBaseTick = newValue }
    }

    var notationGuideScrollScheduleTaskGeneration: Int {
        get { stateStore.notationGuideScrollScheduleTaskGeneration }
        set { stateStore.notationGuideScrollScheduleTaskGeneration = newValue }
    }

    var notationGuideScrollScheduleTimelineEventCount: Int {
        get { stateStore.notationGuideScrollScheduleTimelineEventCount }
        set { stateStore.notationGuideScrollScheduleTimelineEventCount = newValue }
    }
    var manualHighlightTransitionTask: Task<Void, Never>?
    var audioRecognitionGeneration: Int {
        get { stateStore.audioRecognitionGeneration }
        set { stateStore.audioRecognitionGeneration = newValue }
    }

    var isAudioRecognitionRunning: Bool {
        get { stateStore.isAudioRecognitionRunning }
        set { stateStore.isAudioRecognitionRunning = newValue }
    }

    var practiceInputGeneration: Int {
        get { stateStore.practiceInputGeneration }
        set { stateStore.practiceInputGeneration = newValue }
    }

    var isPracticeInputRunning: Bool {
        get { stateStore.isPracticeInputRunning }
        set { stateStore.isPracticeInputRunning = newValue }
    }

    var practiceInputActiveSinceUptimeSeconds: TimeInterval? {
        get { stateStore.practiceInputActiveSinceUptimeSeconds }
        set { stateStore.practiceInputActiveSinceUptimeSeconds = newValue }
    }

    var practiceInputLastResetStepIndex: Int? {
        get { stateStore.practiceInputLastResetStepIndex }
        set { stateStore.practiceInputLastResetStepIndex = newValue }
    }

    var practiceInputDebugLastLoggedAtUptimeSeconds: TimeInterval {
        get { stateStore.practiceInputDebugLastLoggedAtUptimeSeconds }
        set { stateStore.practiceInputDebugLastLoggedAtUptimeSeconds = newValue }
    }

    var practiceInputDebugLastMessage: String? {
        get { stateStore.practiceInputDebugLastMessage }
        set { stateStore.practiceInputDebugLastMessage = newValue }
    }

    var audioRecognitionSuppressUntil: Date? {
        get { stateStore.audioRecognitionSuppressUntil }
        set { stateStore.audioRecognitionSuppressUntil = newValue }
    }
    let audioRecognitionSuppressDuration: TimeInterval = 0.6
    let audioRecognitionEnabledSnapshot = MusicXMLRealisticPlaybackDefaults.audioRecognitionEnabled
    var practiceAudioRecognitionDetectorModeSnapshot: PracticeAudioRecognitionDetectorMode {
        get { stateStore.practiceAudioRecognitionDetectorModeSnapshot }
        set { stateStore.practiceAudioRecognitionDetectorModeSnapshot = newValue }
    }

    var harmonicTemplateTuningProfileSnapshot: HarmonicTemplateTuningProfile {
        get { stateStore.harmonicTemplateTuningProfileSnapshot }
        set { stateStore.harmonicTemplateTuningProfileSnapshot = newValue }
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
        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.sequencerPlaybackService = sequencerPlaybackService
        self.audioRecognitionService = audioRecognitionService
        self.practiceInputEventSource = practiceInputEventSource
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator
        self.handPianoActivityGate = handPianoActivityGate
        self.manualAdvanceModeProvider = manualAdvanceModeProvider
        bindAudioRecognitionStreamsIfNeeded()
        bindPracticeInputStreamsIfNeeded()
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
        stopAutoplayTask()
        stopAutoplayAudio()
        handle(effect: .stopAudioRecognition)
        handle(effect: .stopPracticeInput)

        audioRecognitionEventsTask?.cancel()
        audioRecognitionEventsTask = nil
        audioRecognitionStatusTask?.cancel()
        audioRecognitionStatusTask = nil
        audioRecognitionDebugTask?.cancel()
        audioRecognitionDebugTask = nil

        practiceInputMIDI1EventsTask?.cancel()
        practiceInputMIDI1EventsTask = nil
        practiceInputMIDI2EventsTask?.cancel()
        practiceInputMIDI2EventsTask = nil
    }

    private func handle(effect: PracticeSessionEffect) {
        switch effect {
        case .refreshPracticeInput:
            refreshPracticeInputForCurrentState()
        case .refreshAudioRecognition:
            refreshAudioRecognitionForCurrentState()
        case let .playCurrentStepSound(applyRecognitionSuppress):
            playCurrentStepSound(applyRecognitionSuppress: applyRecognitionSuppress)
        case .stopTransientWork:
            stopManualReplayTask()
            stopAutoplayTask()
            stopAutoplayAudio()
        case .stopAudioRecognition:
            stopAudioRecognition()
        case .stopPracticeInput:
            stopPracticeInput()
        }
    }

    var currentStepIndex: Int {
        get { stateStore.currentStepIndex }
        set { stateStore.currentStepIndex = newValue }
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

    var notationMeasureSpans: [MusicXMLMeasureSpan] {
        measureSpans
    }

    var currentGrandStaffNotationContext: GrandStaffNotationContext? {
        guard let attributeTimeline else { return nil }

        let tick = currentPianoHighlightGuide?.tick ?? currentStep?.tick ?? 0

        let trebleClefEvent = attributeTimeline.clef(atTick: tick, staffNumber: 1)
        let trebleClef = trebleClefEvent.flatMap { Self.notationClefSymbol(for: $0) } ?? "\u{E050}"
        let trebleClefSignToken = trebleClefEvent?.signToken
        let trebleClefLine = trebleClefEvent?.line

        let bassClefEvent = attributeTimeline.clef(atTick: tick, staffNumber: 2)
        let bassClef = bassClefEvent.flatMap { Self.notationClefSymbol(for: $0) } ?? "\u{E062}"
        let bassClefSignToken = bassClefEvent?.signToken
        let bassClefLine = bassClefEvent?.line

        let keySignatureEvent = attributeTimeline.keySignature(atTick: tick)
        let keySignatureText = keySignatureEvent
            .flatMap { Self.notationKeySignatureText(fifths: $0.fifths) }
        let keySignatureFifths = keySignatureEvent?.fifths
        let timeSignatureText = attributeTimeline.timeSignature(atTick: tick).map { "\($0.beats)/\($0.beatType)" }

        return GrandStaffNotationContext(
            trebleClefSymbol: trebleClef,
            bassClefSymbol: bassClef,
            trebleClefSignToken: trebleClefSignToken,
            trebleClefLine: trebleClefLine,
            bassClefSignToken: bassClefSignToken,
            bassClefLine: bassClefLine,
            keySignatureText: keySignatureText,
            keySignatureFifths: keySignatureFifths,
            timeSignatureText: timeSignatureText
        )
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

    private static func notationClefSymbol(for event: MusicXMLClefEvent) -> String? {
        guard let sign = event.signToken, sign.isEmpty == false else { return nil }
        switch sign.uppercased() {
            case "G":
                return "\u{E050}" // SMuFL gClef
            case "F":
                return "\u{E062}" // SMuFL fClef
            case "C":
                return "\u{E05C}" // SMuFL cClef
            default:
                return nil
        }
    }

    private static func notationKeySignatureText(fifths: Int) -> String? {
        if fifths == 0 {
            return nil
        }
        if fifths > 0 {
            return String(repeating: "\u{E262}", count: min(fifths, 7)) // SMuFL accidentalSharp
        }
        return String(repeating: "\u{E260}", count: min(abs(fifths), 7)) // SMuFL accidentalFlat
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
        latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
        keyContactDetectionService.reset()
        realPianoContactDetectionService.reset()
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
        latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
        keyContactDetectionService.reset()
        realPianoContactDetectionService.reset()
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
        latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
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

    func uniqueMIDINotesByHand(in step: PracticeStep) -> (right: [Int], left: [Int]) {
        var right: Set<Int> = []
        var left: Set<Int> = []

        for note in step.notes {
            if note.hand == .left {
                left.insert(note.midiNote)
            } else {
                right.insert(note.midiNote)
            }
        }

        return (right: right.sorted(), left: left.sorted())
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
