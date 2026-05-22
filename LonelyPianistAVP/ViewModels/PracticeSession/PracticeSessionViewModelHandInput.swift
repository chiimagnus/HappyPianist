import Foundation
import simd

extension PracticeSessionViewModel {
    func handleFingerTipPositions(
        _ fingerTips: [String: SIMD3<Float>],
        isVirtualPiano: Bool = false,
        at timestamp: Date = .now
    ) -> Set<Int> {
        guard let keyboardGeometry = self.keyboardGeometry else { return [] }

        if isVirtualPiano {
            return virtualPianoInputController?.handleFingerTips(
                fingerTips,
                keyboardGeometry: keyboardGeometry,
                at: timestamp,
                isHandSeparatedStepMatchingEnabled: isHandSeparatedStepMatchingEnabled,
                practiceHandMode: practiceHandMode
            ) ?? []
        }

        let detected = pressDetectionService.detectPressedNotes(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp
        )
        updateLatestNoteOnMIDINotes(detected)
        self.latestKeyContactResult = realPianoContactDetectionService.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry
        )

        if detected.isEmpty == false {
            self.pressedNotes = detected
            handGateController?.updateHandGateState(
                fingerTips: fingerTips,
                keyboardGeometry: keyboardGeometry,
                exactPressedNotes: detected
            )
            handGateController?.registerChordAttemptIfNeeded(
                pressedNotes: detected,
                at: timestamp,
                isHandSeparatedStepMatchingEnabled: isHandSeparatedStepMatchingEnabled,
                practiceHandMode: practiceHandMode
            )
        } else {
            handGateController?.updateHandGateState(
                fingerTips: fingerTips,
                keyboardGeometry: keyboardGeometry,
                exactPressedNotes: []
            )
        }

        return detected
    }
}
