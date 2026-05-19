import Foundation

extension PracticeSessionViewModel {
    func refreshPracticeInputForCurrentState() {
        midiInputCoordinator?.refresh(
            for: .init(
                practiceState: state,
                autoplayState: autoplayState,
                isManualReplayPlaying: isManualReplayPlaying,
                currentStepIndex: currentStepIndex,
                expectedNotes: currentStep?.notes ?? []
            )
        )
    }

    func stopPracticeInput() {
        midiInputCoordinator?.stop()
    }
}
