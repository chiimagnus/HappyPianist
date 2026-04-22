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
    private(set) var keyRegions: [PianoKeyRegion] = []
    private(set) var pressedNotes: Set<Int> = []
    private(set) var feedbackState: VisualFeedbackState = .none
    private(set) var isSustainPedalDown = false
    var noteMatchTolerance: Int = 1

    private let pressDetectionService: PressDetectionServiceProtocol
    private let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    private let sleeper: SleeperProtocol
    private let noteAudioPlayer: PracticeNoteAudioPlayerProtocol?
    private var feedbackResetTask: Task<Void, Never>?
    private var autoplayTask: Task<Void, Never>?
    private var tempoMap: MusicXMLTempoMap?
    private var pedalTimeline: MusicXMLPedalTimeline?
    private var didLogMissingTempoMap = false

    init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        noteAudioPlayer: PracticeNoteAudioPlayerProtocol?
    ) {
        self.pressDetectionService = pressDetectionService
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.sleeper = sleeper
        self.noteAudioPlayer = noteAudioPlayer
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

    func setSteps(_ steps: [PracticeStep]) {
        setSteps(steps, tempoMap: nil, pedalTimeline: nil)
    }

    func setSteps(_ steps: [PracticeStep], tempoMap: MusicXMLTempoMap?, pedalTimeline: MusicXMLPedalTimeline? = nil) {
        if state == .completed, self.steps == steps, steps.isEmpty == false {
            return
        }

        let shouldResetProgress = self.steps != steps

        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        stopAutoplayTask()
        chordAttemptAccumulator.reset()
        self.steps = steps
        self.tempoMap = tempoMap
        self.pedalTimeline = pedalTimeline

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

    func applyCalibration(_ calibration: PianoCalibration, keyRegions: [PianoKeyRegion]) {
        self.calibration = calibration
        self.keyRegions = keyRegions
        if steps.isEmpty == false, state != .completed, state != .guiding(stepIndex: currentStepIndex) {
            state = .ready
        }
    }

    func clearCalibration() {
        calibration = nil
        keyRegions = []
        pressedNotes.removeAll()
    }

    func resetSession() {
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        stopAutoplayTask()
        chordAttemptAccumulator.reset()
        steps = []
        tempoMap = nil
        pedalTimeline = nil
        calibration = nil
        keyRegions = []
        pressedNotes.removeAll()
        feedbackState = .none
        isSustainPedalDown = false
        currentStepIndex = 0
        state = .idle
    }

    func startGuidingIfReady() {
        guard state == .ready, steps.isEmpty == false else { return }
        currentStepIndex = 0
        state = .guiding(stepIndex: currentStepIndex)
        playCurrentStepSound()
        startAutoplayTaskIfNeeded()
    }

    func skip() {
        stopAutoplayTask()
        advanceToNextStep()
        startAutoplayTaskIfNeeded()
    }

    func playCurrentStepSound() {
        guard let currentStep else { return }
        noteAudioPlayer?.play(midiNotes: currentStep.notes.map(\.midiNote))
    }

    func setAutoplayEnabled(_ isEnabled: Bool) {
        if isEnabled {
            autoplayState = .playing
            startAutoplayTaskIfNeeded()
        } else {
            autoplayState = .off
            stopAutoplayTask()
        }
    }

    func handleFingerTipPositions(_ fingerTips: [String: SIMD3<Float>], at timestamp: Date = .now) -> Set<Int> {
        guard keyRegions.isEmpty == false else { return [] }
        let detected = pressDetectionService.detectPressedNotes(
            fingerTips: fingerTips,
            keyRegions: keyRegions,
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
            playCurrentStepSound()
        } else {
            currentStepIndex = steps.count
            pressedNotes.removeAll()
            state = .completed
            stopAutoplayTask()
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

            while Task.isCancelled == false {
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }

                let index = currentStepIndex
                guard index + 1 < steps.count else { break }

                let fromTick = steps[index].tick
                let toTick = steps[index + 1].tick
                let waitSeconds = tempoMap.durationSeconds(fromTick: fromTick, toTick: toTick)

                if waitSeconds > 0 {
                    try? await sleeper.sleep(for: .seconds(waitSeconds))
                } else {
                    await Task.yield()
                }

                guard Task.isCancelled == false else { break }
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }

                advanceToNextStep()
            }

            autoplayTask = nil
        }
    }

    private func stopAutoplayTask() {
        autoplayTask?.cancel()
        autoplayTask = nil
    }

    private func resolvedTempoMap() -> MusicXMLTempoMap {
        if let tempoMap {
            return tempoMap
        }

        if didLogMissingTempoMap == false {
            didLogMissingTempoMap = true
            #if DEBUG
            print("PracticeSessionViewModel: tempoMap missing; falling back to default bpm=120")
            #endif
        }

        return MusicXMLTempoMap(tempoEvents: [])
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
