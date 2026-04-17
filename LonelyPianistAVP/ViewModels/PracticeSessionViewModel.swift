import Foundation
import Observation
import simd

@MainActor
@Observable
final class PracticeSessionViewModel {
    enum PracticeState: Equatable {
        case idle
        case ready
        case guiding(stepIndex: Int)
    }

    private(set) var state: PracticeState = .idle
    private(set) var steps: [PracticeStep] = []
    private(set) var calibration: PianoCalibration?
    private(set) var keyRegions: [PianoKeyRegion] = []
    private(set) var pressedNotes: Set<Int> = []
    var noteMatchTolerance: Int = 1

    private let pressDetectionService: PressDetectionServiceProtocol
    private let stepMatcher: StepMatcherProtocol

    init(
        pressDetectionService: PressDetectionServiceProtocol = PressDetectionService(),
        stepMatcher: StepMatcherProtocol = StepMatcher()
    ) {
        self.pressDetectionService = pressDetectionService
        self.stepMatcher = stepMatcher
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
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    func configure(steps: [PracticeStep], calibration: PianoCalibration, keyRegions: [PianoKeyRegion]) {
        self.steps = steps
        self.calibration = calibration
        self.keyRegions = keyRegions
        currentStepIndex = 0
        state = (steps.isEmpty || keyRegions.isEmpty) ? .idle : .ready
    }

    func startGuidingIfReady() {
        guard state == .ready, steps.isEmpty == false else { return }
        currentStepIndex = 0
        state = .guiding(stepIndex: currentStepIndex)
    }

    func skip() {
        advanceToNextStep()
    }

    func markCorrect() {
        advanceToNextStep()
    }

    func handleFingerTipPositions(_ fingerTips: [String: SIMD3<Float>], at timestamp: Date = .now) -> Set<Int> {
        let detected = pressDetectionService.detectPressedNotes(
            fingerTips: fingerTips,
            keyRegions: keyRegions,
            at: timestamp
        )
        if detected.isEmpty == false {
            pressedNotes = detected
            if let currentStep {
                let expected = currentStep.notes.map(\.midiNote)
                let isMatched = stepMatcher.matches(
                    expectedNotes: expected,
                    pressedNotes: detected,
                    tolerance: noteMatchTolerance
                )
                if isMatched {
                    advanceToNextStep()
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
        if currentStepIndex + 1 < steps.count {
            currentStepIndex += 1
            state = .guiding(stepIndex: currentStepIndex)
        } else {
            currentStepIndex = steps.count - 1
            state = .ready
        }
    }
}
