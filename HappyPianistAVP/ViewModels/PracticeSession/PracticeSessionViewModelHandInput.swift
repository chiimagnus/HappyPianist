import Foundation
import simd

extension PracticeSessionViewModel {
    func handleFingerTipPositions(
        _ fingerTips: FingerTipsSnapshot,
        isVirtualPiano: Bool = false,
        at timestamp: PerformanceMonotonicInstant = PerformanceClock.live().now()
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

        let observations = realPianoContactDetectionService.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp
        )
        self.latestKeyContactObservations = observations
        let activeMIDINotes = observations.activeMIDINotes
        updateLatestNoteOnMIDINotes(observations.startedMIDINotes)

        handGateController?.updateHandGateState(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: activeMIDINotes,
            at: timestamp
        )

        self.pressedNotes = activeMIDINotes
        handGateController?.registerChordAttemptIfNeeded(
            observations: observations,
            at: timestamp,
            practiceHandMode: practiceHandMode
        )

        return activeMIDINotes
    }
}
