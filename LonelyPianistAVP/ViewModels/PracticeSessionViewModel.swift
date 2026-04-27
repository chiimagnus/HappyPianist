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

    private(set) var state: PracticeState = .idle
    private(set) var steps: [PracticeStep] = []
    private(set) var autoplayState: AutoplayState = .off
    private(set) var calibration: PianoCalibration?
    private(set) var keyboardGeometry: PianoKeyboardGeometry?
    private(set) var pressedNotes: Set<Int> = []
    private(set) var feedbackState: VisualFeedbackState = .none
    private(set) var isSustainPedalDown = false
    private(set) var audioRecognitionErrorMessage: String?
    private(set) var audioPlaybackErrorMessage: String?
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
    private let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    private let sleeper: SleeperProtocol
    private let noteAudioPlayer: PracticeNoteAudioPlayerProtocol?
    private let noteOutput: PracticeMIDINoteOutputProtocol?
    private let audioRecognitionService: PracticeAudioRecognitionServiceProtocol?
    private let audioStepAttemptAccumulator: AudioStepAttemptAccumulator
    private let handPianoActivityGate: HandPianoActivityGate
    private var feedbackResetTask: Task<Void, Never>?
    private var autoplayTask: Task<Void, Never>?
    private var audioRecognitionEventsTask: Task<Void, Never>?
    private var audioRecognitionStatusTask: Task<Void, Never>?
    private var audioRecognitionDebugTask: Task<Void, Never>?
    private var noteOffTasksByMIDI: [Int: Task<Void, Never>] = [:]
    private var tempoMap: MusicXMLTempoMap?
    private var pedalTimeline: MusicXMLPedalTimeline?
    private var fermataTimeline: MusicXMLFermataTimeline?
    private var attributeTimeline: MusicXMLAttributeTimeline?
    private var slurTimeline: MusicXMLSlurTimeline?
    private var noteSpanOffTickByOnsetKey: [NoteSpanOnsetKey: Int] = [:]
    private var activeNoteOffTickByMIDI: [Int: Int] = [:]
    private var pendingReleaseOffTickByMIDI: [Int: Int] = [:]
    private var pendingAutoplayOnsetsByTick: [Int: [PracticeStepNote]] = [:]
    private(set) var highlightGuides: [PianoHighlightGuide] = []
    private var currentHighlightGuideIndex: Int?
    private var manualHighlightTransitionTask: Task<Void, Never>?
    private var audioRecognitionGeneration = 0
    private var isAudioRecognitionRunning = false
    private var audioRecognitionSuppressUntil: Date?
    private let audioRecognitionSuppressDuration: TimeInterval = 0.6
    private var practiceAudioRecognitionEnabledSnapshot = true
    private var practiceAudioRecognitionDetectorModeSnapshot: PracticeAudioRecognitionDetectorMode = .harmonicTemplate
    private var harmonicTemplateTuningProfileSnapshot: HarmonicTemplateTuningProfile = .lowLatencyDefault

    init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        noteAudioPlayer: PracticeNoteAudioPlayerProtocol?,
        noteOutput: PracticeMIDINoteOutputProtocol? = nil,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator? = nil,
        handPianoActivityGate: HandPianoActivityGate? = nil
    ) {
        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.noteAudioPlayer = noteAudioPlayer
        self.noteOutput = noteOutput ?? (noteAudioPlayer as? PracticeMIDINoteOutputProtocol)
        self.audioRecognitionService = audioRecognitionService
        self.audioStepAttemptAccumulator = audioStepAttemptAccumulator ?? AudioStepAttemptAccumulator()
        self.handPianoActivityGate = handPianoActivityGate ?? HandPianoActivityGate()
        bindAudioRecognitionStreamsIfNeeded()
    }

    convenience init() {
        self.init(
            pressDetectionService: PressDetectionService(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            noteAudioPlayer: SoundFontPracticeNoteAudioPlayer(soundFontResourceName: "SalC5Light2"),
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

    func setSteps(_ steps: [PracticeStep]) {
        setSteps(steps, tempoMap: nil, pedalTimeline: nil)
    }

    func setSteps(_ steps: [PracticeStep], tempoMap: MusicXMLTempoMap?, pedalTimeline: MusicXMLPedalTimeline? = nil) {
        setSteps(
            steps,
            tempoMap: tempoMap,
            pedalTimeline: pedalTimeline,
            fermataTimeline: nil,
            attributeTimeline: nil,
            slurTimeline: nil,
            noteSpans: []
        )
    }

    func setSteps(
        _ steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap?,
        pedalTimeline: MusicXMLPedalTimeline? = nil,
        fermataTimeline: MusicXMLFermataTimeline? = nil,
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        slurTimeline: MusicXMLSlurTimeline? = nil,
        noteSpans: [MusicXMLNoteSpan] = [],
        highlightGuides: [PianoHighlightGuide] = []
    ) {
        if state == .completed, self.steps == steps, steps.isEmpty == false {
            return
        }

        let shouldResetProgress = self.steps != steps

        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        manualHighlightTransitionTask?.cancel()
        manualHighlightTransitionTask = nil
        chordAttemptAccumulator.reset()
        self.steps = steps
        self.tempoMap = tempoMap
        self.pedalTimeline = pedalTimeline
        self.fermataTimeline = fermataTimeline
        self.attributeTimeline = attributeTimeline
        self.slurTimeline = slurTimeline
        noteSpanOffTickByOnsetKey = Self.makeNoteSpanOffTickByOnsetKey(noteSpans)
        self.highlightGuides = highlightGuides.isEmpty ? PianoHighlightGuideBuilderService.makeFallbackGuides(from: steps) : highlightGuides
        currentHighlightGuideIndex = nil
        pendingAutoplayOnsetsByTick = [:]

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
        stopAutoplayTask()
        stopAutoplayAudio()
        stopAudioRecognition()
        chordAttemptAccumulator.reset()
        steps = []
        tempoMap = nil
        pedalTimeline = nil
        fermataTimeline = nil
        attributeTimeline = nil
        slurTimeline = nil
        noteSpanOffTickByOnsetKey = [:]
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
        currentStepIndex = 0
        state = .idle
        pendingAutoplayOnsetsByTick = [:]
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

    func startGuidingIfReady() {
        guard state == .ready, steps.isEmpty == false else { return }
        currentStepIndex = 0
        setCurrentHighlightGuideForStepIndex(currentStepIndex)
        state = .guiding(stepIndex: currentStepIndex)
        if autoplayState == .playing {
            refreshAudioRecognitionForCurrentState()
            prepareAutoplayOnsetsForCurrentStep()
        } else {
            prepareAudioRecognitionSuppressWindowForPlayback()
            refreshAudioRecognitionForCurrentState()
            playCurrentStepSound(applyRecognitionSuppress: false)
        }
        startAutoplayTaskIfNeeded()
    }

    func skip() {
        stopAutoplayTask()
        stopAutoplayAudio()
        advanceToNextStep()
        startAutoplayTaskIfNeeded()
    }

    func playCurrentStepSound() {
        playCurrentStepSound(applyRecognitionSuppress: true)
    }

    private func playCurrentStepSound(applyRecognitionSuppress: Bool) {
        guard let currentStep else { return }
        guard audioPlaybackErrorMessage == nil else { return }
        if applyRecognitionSuppress {
            prepareAudioRecognitionSuppressWindowForPlayback()
        }
        do {
            try noteAudioPlayer?.play(midiNotes: currentStep.notes.map(\.midiNote))
        } catch {
            recordPlaybackError(error)
        }
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            autoplayState = .playing
            let tick = currentStep?.tick ?? 0
            isSustainPedalDown = pedalTimeline?.isDown(atTick: tick) ?? false
            if case .guiding = state {
                prepareAutoplayOnsetsForCurrentStep()
            }
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
            if autoplayState == .off, let currentStep {
                let expected = currentStep.notes.map(\.midiNote)
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
                prepareAutoplayOnsetsForCurrentStep()
            } else {
                prepareAudioRecognitionSuppressWindowForPlayback()
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

    private func startAutoplayTaskIfNeeded() {
        guard autoplayState == .playing else { return }
        guard case .guiding = state else { return }
        guard steps.count >= 2 else { return }

        if autoplayTask != nil {
            return
        }

        let tempoMap = resolvedTempoMap()

        autoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentTick = steps[currentStepIndex].tick
            isSustainPedalDown = pedalTimeline?.isDown(atTick: currentTick) ?? false

            while Task.isCancelled == false {
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }

                let index = currentStepIndex
                guard index + 1 < steps.count else { break }

                let nextStepTick = steps[index + 1].tick
                let nextPedalChange = pedalTimeline?.nextChange(afterTick: currentTick)
                let nextPedalTick = nextPedalChange?.tick ?? Int.max
                let nextPedalReleaseTick = pedalTimeline?.nextReleaseEdge(afterTick: currentTick) ?? Int.max
                let nextNoteOffTick = activeNoteOffTickByMIDI.values.min() ?? Int.max
                let nextNoteOnTick = pendingAutoplayOnsetsByTick.keys.min() ?? Int.max
                let nextEventTick = min(
                    nextStepTick,
                    nextPedalTick,
                    nextPedalReleaseTick,
                    nextNoteOffTick,
                    nextNoteOnTick
                )

                let waitSeconds = tempoMap.durationSeconds(fromTick: currentTick, toTick: nextEventTick)

                if waitSeconds > 0 {
                    try? await sleeper.sleep(for: .seconds(waitSeconds))
                } else {
                    await Task.yield()
                }

                guard Task.isCancelled == false else { break }
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }

                currentTick = nextEventTick
                advanceAutoplayHighlightGuides(upToTick: currentTick)

                if nextPedalTick == nextEventTick, let change = nextPedalChange {
                    isSustainPedalDown = change.isDown
                }

                if nextNoteOffTick == nextEventTick {
                    handleDueNoteOffs(atTick: currentTick)
                }

                if nextPedalReleaseTick == nextEventTick {
                    releasePendingNotesIfNeeded(atTick: currentTick)
                }

                if nextNoteOnTick == nextEventTick {
                    playPendingAutoplayOnsetsIfDue(atTick: currentTick)
                }

                if nextStepTick == nextEventTick {
                    let staffs = Set(steps[index].notes.map { $0.staff ?? 1 })
                    let fermataDelay = fermataTimeline?.extraHoldSeconds(
                        atTick: steps[index].tick,
                        staffs: staffs,
                        tempoMap: tempoMap
                    ) ?? 0
                    if fermataDelay > 0 {
                        try? await sleeper.sleep(for: .seconds(fermataDelay))
                    }

                    guard Task.isCancelled == false else { break }
                    guard autoplayState == .playing else { break }
                    guard case .guiding = state else { break }

                    advanceToNextStep()
                    guard case .guiding = state else { break }
                    currentTick = steps[currentStepIndex].tick
                }
            }

            autoplayTask = nil
        }
    }

    private func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else {
            currentHighlightGuideIndex = nil
            return
        }
        let tick = steps[stepIndex].tick
        currentHighlightGuideIndex = highlightGuides.firstIndex { guide in
            guide.practiceStepIndex == stepIndex && guide.kind == .trigger
        } ?? highlightGuides.firstIndex { guide in
            guide.tick >= tick && guide.kind == .trigger
        } ?? highlightGuides.firstIndex { guide in
            guide.tick >= tick
        }
    }

    private func updateHighlightGuideAfterStepAdvance(previousTick: Int, nextStepIndex: Int) {
        guard autoplayState == .off else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }
        manualHighlightTransitionTask?.cancel()
        guard steps.indices.contains(nextStepIndex) else {
            currentHighlightGuideIndex = nil
            return
        }
        let nextTick = steps[nextStepIndex].tick
        let transitionIndex = highlightGuides.firstIndex { guide in
            guide.tick > previousTick && guide.tick < nextTick && (guide.kind == .release || guide.kind == .gap)
        }
        guard let transitionIndex else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }
        currentHighlightGuideIndex = transitionIndex
        manualHighlightTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await sleeper.sleep(for: .seconds(0.12))
            guard Task.isCancelled == false else { return }
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            manualHighlightTransitionTask = nil
        }
    }

    private func advanceAutoplayHighlightGuides(upToTick tick: Int) {
        guard highlightGuides.isEmpty == false else { return }
        let index = highlightGuides.lastIndex { guide in
            guide.tick <= tick
        }
        currentHighlightGuideIndex = index
    }
    private func resolvedTempoMap() -> MusicXMLTempoMap {
        tempoMap ?? MusicXMLTempoMap(tempoEvents: [])
    }

    private func stopAutoplayTask() {
        autoplayTask?.cancel()
        autoplayTask = nil
    }

    private func stopAutoplayAudio() {
        for task in noteOffTasksByMIDI.values {
            task.cancel()
        }
        noteOffTasksByMIDI = [:]
        activeNoteOffTickByMIDI = [:]
        pendingReleaseOffTickByMIDI = [:]
        pendingAutoplayOnsetsByTick = [:]
        noteOutput?.allNotesOff()
    }

    private func prepareAutoplayOnsetsForCurrentStep() {
        guard let currentStep else { return }
        guard autoplayState == .playing else { return }
        guard let noteOutput else { return }
        guard audioPlaybackErrorMessage == nil else { return }

        pendingAutoplayOnsetsByTick = Dictionary(
            grouping: currentStep.notes,
            by: { currentStep.tick + $0.onTickOffset }
        )

        for note in currentStep.notes {
            noteOffTasksByMIDI[note.midiNote]?.cancel()
            noteOffTasksByMIDI[note.midiNote] = nil

            if activeNoteOffTickByMIDI[note.midiNote] != nil || pendingReleaseOffTickByMIDI[note.midiNote] != nil {
                noteOutput.noteOff(midi: note.midiNote)
            }

            activeNoteOffTickByMIDI[note.midiNote] = nil
            pendingReleaseOffTickByMIDI[note.midiNote] = nil
        }

        playPendingAutoplayOnsetsIfDue(atTick: currentStep.tick)
    }

    private func playPendingAutoplayOnsetsIfDue(atTick tick: Int) {
        guard autoplayState == .playing else { return }
        guard let noteOutput else { return }
        guard audioPlaybackErrorMessage == nil else { return }
        guard let notes = pendingAutoplayOnsetsByTick.removeValue(forKey: tick) else { return }

        for note in notes {
            do {
                try noteOutput.noteOn(midi: note.midiNote, velocity: note.velocity)
                let offTick = resolveOffTick(midi: note.midiNote, staff: note.staff, onTick: tick)
                activeNoteOffTickByMIDI[note.midiNote] = offTick
            } catch {
                recordPlaybackError(error)
                break
            }
        }
    }

    private func handleDueNoteOffs(atTick tick: Int) {
        let due = activeNoteOffTickByMIDI.filter { _, offTick in
            offTick <= tick
        }

        for (midi, offTick) in due {
            activeNoteOffTickByMIDI[midi] = nil

            if isSustainPedalDown {
                pendingReleaseOffTickByMIDI[midi] = offTick
            } else {
                scheduleNoteOff(midi: midi)
            }
        }
    }

    private func releasePendingNotesIfNeeded(atTick tick: Int) {
        let releasable = pendingReleaseOffTickByMIDI.filter { _, offTick in
            offTick <= tick
        }

        for (midi, _) in releasable {
            pendingReleaseOffTickByMIDI[midi] = nil
            scheduleNoteOff(midi: midi)
        }
    }

    private func scheduleNoteOff(midi: Int) {
        guard let noteOutput else { return }

        noteOffTasksByMIDI[midi]?.cancel()
        noteOffTasksByMIDI[midi] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await sleeper.sleep(for: .seconds(PracticeMIDINoteOutputConstants.releaseSeconds))
            guard Task.isCancelled == false else { return }
            noteOutput.noteOff(midi: midi)
            noteOffTasksByMIDI[midi] = nil
        }
    }

    private func resolveOffTick(midi: Int, staff: Int?, onTick: Int) -> Int {
        let key = NoteSpanOnsetKey(onTick: onTick, midiNote: midi, staff: staff ?? 1)
        return noteSpanOffTickByOnsetKey[key] ?? onTick
    }

    private static func makeNoteSpanOffTickByOnsetKey(_ spans: [MusicXMLNoteSpan]) -> [NoteSpanOnsetKey: Int] {
        var result: [NoteSpanOnsetKey: Int] = [:]
        result.reserveCapacity(spans.count)

        for span in spans {
            let key = NoteSpanOnsetKey(onTick: span.onTick, midiNote: span.midiNote, staff: span.staff)
            result[key] = max(result[key] ?? Int.min, span.offTick)
        }

        return result
    }

    private struct NoteSpanOnsetKey: Hashable {
        let onTick: Int
        let midiNote: Int
        let staff: Int
    }

    private func recordPlaybackError(_ error: Error) {
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

    private func refreshAudioRecognitionForCurrentState() {
        guard let audioRecognitionService else { return }
        guard isPracticeAudioRecognitionEnabled else {
            stopAudioRecognition()
            return
        }
        guard autoplayState == .off else {
            stopAudioRecognition()
            return
        }
        guard case .guiding = state, let currentStep else {
            stopAudioRecognition()
            return
        }

        let expectedMIDINotes = currentStep.notes.map(\.midiNote)
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
        practiceAudioRecognitionEnabledSnapshot = Self.readPracticeAudioRecognitionEnabled()
        practiceAudioRecognitionDetectorModeSnapshot = Self.readPracticeAudioRecognitionDetectorMode()
        harmonicTemplateTuningProfileSnapshot = Self.profile(for: practiceAudioRecognitionDetectorModeSnapshot)
        audioRecognitionService?.configureDetectorMode(
            practiceAudioRecognitionDetectorModeSnapshot,
            profile: harmonicTemplateTuningProfileSnapshot
        )
        refreshAudioRecognitionForCurrentState()
    }

    private func stopAudioRecognition() {
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
        guard event.generation == audioRecognitionGeneration else { return }
        if let audioRecognitionSuppressUntil, event.timestamp <= audioRecognitionSuppressUntil {
            decisionLogger.debug("audio event suppressed generation=\(event.generation, privacy: .public)")
            return
        }
        guard let currentStep else { return }

        let expectedMIDINotes = currentStep.notes.map(\.midiNote)
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
        practiceAudioRecognitionEnabledSnapshot
    }

    private static func readPracticeAudioRecognitionEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: "practiceAudioRecognitionEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "practiceAudioRecognitionEnabled")
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
