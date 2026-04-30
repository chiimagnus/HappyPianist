import Foundation
import simd

extension PracticeSessionViewModel {
    func handleFingerTipPositions(
        _ fingerTips: [String: SIMD3<Float>],
        isVirtualPiano: Bool = false,
        at timestamp: Date = .now
    ) -> Set<Int> {
        guard let keyboardGeometry else { return [] }

        if isVirtualPiano {
            return handleVirtualPianoFingerTips(
                fingerTips,
                keyboardGeometry: keyboardGeometry,
                at: timestamp
            )
        }

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

    private func handleVirtualPianoFingerTips(
        _ fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry,
        at timestamp: Date
    ) -> Set<Int> {
        let result = keyContactDetectionService.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry
        )

        let shouldPlayLiveNotes = autoplayState == .off && isManualReplayPlaying == false

        if shouldPlayLiveNotes, result.started.isEmpty == false {
            try? sequencerPlaybackService.startLiveNotes(midiNotes: result.started)
        }
        if result.ended.isEmpty == false {
            sequencerPlaybackService.stopLiveNotes(midiNotes: result.ended)
        }

        pressedNotes = result.down
        handGateState = handPianoActivityGate.evaluate(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: result.down
        )

        if result.started.isEmpty == false,
           autoplayState == .off,
           isManualReplayPlaying == false,
           let currentStep
        {
            let expected = uniqueMIDINotes(in: currentStep)
            let isMatched = chordAttemptAccumulator.register(
                pressedNotes: result.started,
                expectedNotes: expected,
                tolerance: noteMatchTolerance,
                at: timestamp
            )
            if isMatched {
                setFeedback(.correct)
                advanceToNextStep()
            } else {
                let unrelatedPressDetected = result.started.contains { pressed in
                    expected.contains(where: { abs($0 - pressed) <= noteMatchTolerance }) == false
                }
                if unrelatedPressDetected {
                    setFeedback(.wrong)
                }
            }
        }

        return result.down
    }
}
