import Foundation
import simd

extension PracticeSessionViewModel {
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
}
