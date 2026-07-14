import Foundation
import simd

extension PracticeSessionViewModel {
    func handleFingerTipPositions(
        _ fingerTips: FingerTipsSnapshot,
        isVirtualPiano: Bool = false,
        at timestamp: Date = .now
    ) -> Set<Int> {
        guard let keyboardGeometry = self.keyboardGeometry else { return [] }

        if isVirtualPiano {
            return virtualPianoInputController?.handleFingerTips(
                fingerTips,
                keyboardGeometry: keyboardGeometry,
                at: timestamp,
                practiceHandMode: practiceHandMode
            ) ?? []
        }

        let detected = pressDetectionService.detectPressedNotes(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp
        )
        updateLatestNoteOnMIDINotes(detected)
        latestKeyContactResult = realPianoContactDetectionService.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry
        )

        handGateController?.updateHandGateState(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: detected
        )

        if detected.isEmpty == false {
            pressedNotes = detected
            handGateController?.registerChordAttemptIfNeeded(
                pressedNotes: detected,
                at: timestamp,
                practiceHandMode: practiceHandMode
            )
        }

        return detected
    }

}
