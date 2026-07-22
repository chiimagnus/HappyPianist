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
            let activeMIDINotes = virtualPianoInputController?.handleFingerTips(
                fingerTips,
                keyboardGeometry: keyboardGeometry,
                at: timestamp,
                practiceHandMode: practiceHandMode
            ) ?? []
            recordHandPerformanceObservations(self.latestKeyContactObservations)
            return activeMIDINotes
        }

        let observations = realPianoContactDetectionService.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp
        )
        self.latestKeyContactObservations = observations
        recordHandPerformanceObservations(observations)
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

    func recordHandPerformanceObservations(_ contacts: [PianoKeyContactObservation]) {
        guard case .guiding = self.state,
              let sourceKind = handObservationSourceKind,
              let sessionRecorder
        else { return }
        if hasRegisteredHandCapabilities == false {
            hasRegisteredHandCapabilities = true
            enqueueSessionRecorderEvent(.inputCapabilitiesAvailable(.handContact))
        }
        let adapter = PianoKeyContactPerformanceObservationAdapter()
        let generation = UInt64(max(0, performanceAssessmentLifecycleGeneration))
        let observations = contacts.compactMap { contact -> PerformanceObservation? in
            guard contact.phase != .held else { return nil }
            return adapter.observation(
                from: contact,
                sourceKind: sourceKind,
                generation: generation
            )
        }
        guard observations.isEmpty == false else { return }
        let previousTask = handObservationRecordingTask
        handObservationRecordingTask = Task {
            await previousTask?.value
            for observation in observations {
                await sessionRecorder.record(observation)
            }
        }
    }
}
