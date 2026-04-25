import Foundation
import Observation
import simd

@MainActor
@Observable
final class PracticeSessionViewModel {
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
    private(set) var autoplayHighlightedMIDINotes: Set<Int> = []
    private(set) var audioErrorMessage: String?
    var noteMatchTolerance: Int = 1

    private let pressDetectionService: PressDetectionServiceProtocol
    private let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    private let sleeper: SleeperProtocol
    private let noteAudioPlayer: PracticeNoteAudioPlayerProtocol?
    private let noteOutput: PracticeMIDINoteOutputProtocol?
    private var feedbackResetTask: Task<Void, Never>?
    private var autoplayTask: Task<Void, Never>?
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

    init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        noteAudioPlayer: PracticeNoteAudioPlayerProtocol?,
        noteOutput: PracticeMIDINoteOutputProtocol? = nil
    ) {
        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.noteAudioPlayer = noteAudioPlayer
        self.noteOutput = noteOutput ?? (noteAudioPlayer as? PracticeMIDINoteOutputProtocol)
    }

    convenience init() {
        self.init(
            pressDetectionService: PressDetectionService(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            sleeper: TaskSleeper(),
            noteAudioPlayer: SoundFontPracticeNoteAudioPlayer(soundFontResourceName: "SalC5Light2")
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
        noteSpans: [MusicXMLNoteSpan] = []
    ) {
        if state == .completed, self.steps == steps, steps.isEmpty == false {
            return
        }

        let shouldResetProgress = self.steps != steps

        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        stopAutoplayTask()
        stopAutoplayAudio()
        chordAttemptAccumulator.reset()
        self.steps = steps
        self.tempoMap = tempoMap
        self.pedalTimeline = pedalTimeline
        self.fermataTimeline = fermataTimeline
        self.attributeTimeline = attributeTimeline
        self.slurTimeline = slurTimeline
        noteSpanOffTickByOnsetKey = Self.makeNoteSpanOffTickByOnsetKey(noteSpans)
        pendingAutoplayOnsetsByTick = [:]

        if shouldResetProgress {
            currentStepIndex = 0
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
    }

    func resetSession() {
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        stopAutoplayTask()
        stopAutoplayAudio()
        chordAttemptAccumulator.reset()
        steps = []
        tempoMap = nil
        pedalTimeline = nil
        fermataTimeline = nil
        attributeTimeline = nil
        slurTimeline = nil
        noteSpanOffTickByOnsetKey = [:]
        calibration = nil
        keyboardGeometry = nil
        pressedNotes.removeAll()
        feedbackState = .none
        isSustainPedalDown = false
        audioErrorMessage = nil
        currentStepIndex = 0
        state = .idle
        pendingAutoplayOnsetsByTick = [:]
    }

    func clearAudioError() {
        audioErrorMessage = nil
    }

    func startGuidingIfReady() {
        guard state == .ready, steps.isEmpty == false else { return }
        currentStepIndex = 0
        state = .guiding(stepIndex: currentStepIndex)
        if autoplayState == .playing {
            prepareAutoplayOnsetsForCurrentStep()
        } else {
            playCurrentStepSound()
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
        guard let currentStep else { return }
        guard audioErrorMessage == nil else { return }
        do {
            try noteAudioPlayer?.play(midiNotes: currentStep.notes.map(\.midiNote))
        } catch {
            recordAudioError(error)
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
            if let currentStep {
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
            currentStepIndex += 1
            state = .guiding(stepIndex: currentStepIndex)
            if autoplayState == .playing {
                prepareAutoplayOnsetsForCurrentStep()
            } else {
                playCurrentStepSound()
            }
        } else {
            currentStepIndex = steps.count
            pressedNotes.removeAll()
            state = .completed
            stopAutoplayTask()
            stopAutoplayAudio()
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
        refreshAutoplayHighlightedMIDINotes()
    }

    private func prepareAutoplayOnsetsForCurrentStep() {
        guard let currentStep else { return }
        guard autoplayState == .playing else { return }
        guard let noteOutput else { return }
        guard audioErrorMessage == nil else { return }

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

        refreshAutoplayHighlightedMIDINotes()
    }

    private func playPendingAutoplayOnsetsIfDue(atTick tick: Int) {
        guard autoplayState == .playing else { return }
        guard let noteOutput else { return }
        guard audioErrorMessage == nil else { return }
        guard let notes = pendingAutoplayOnsetsByTick.removeValue(forKey: tick) else { return }

        for note in notes {
            do {
                try noteOutput.noteOn(midi: note.midiNote, velocity: note.velocity)
                let offTick = resolveOffTick(midi: note.midiNote, staff: note.staff, onTick: tick)
                activeNoteOffTickByMIDI[note.midiNote] = offTick
            } catch {
                recordAudioError(error)
                break
            }
        }

        refreshAutoplayHighlightedMIDINotes()
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

        if due.isEmpty == false {
            refreshAutoplayHighlightedMIDINotes()
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

        if releasable.isEmpty == false {
            refreshAutoplayHighlightedMIDINotes()
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
            refreshAutoplayHighlightedMIDINotes()
        }
        refreshAutoplayHighlightedMIDINotes()
    }

    private func refreshAutoplayHighlightedMIDINotes() {
        autoplayHighlightedMIDINotes = Set(activeNoteOffTickByMIDI.keys)
            .union(pendingReleaseOffTickByMIDI.keys)
            .union(noteOffTasksByMIDI.keys)
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

    private func recordAudioError(_ error: Error) {
        guard audioErrorMessage == nil else { return }

        if let localized = error as? LocalizedError, let description = localized.errorDescription,
           description.isEmpty == false
        {
            audioErrorMessage = description
        } else {
            audioErrorMessage = String(describing: error)
        }
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
}
