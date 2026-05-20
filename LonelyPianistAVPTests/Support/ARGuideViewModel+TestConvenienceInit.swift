@testable import LonelyPianistAVP

extension ARGuideViewModel {
    @MainActor
    convenience init(appState: AppState, practiceSetupState: PracticeSetupState) {
        let registry = PianoModeRegistryService(modes: [])
        self.init(
            appState: appState,
            practiceSetupState: practiceSetupState,
            pianoModeRegistry: registry,
            makePracticeSessionViewModel: { _ in
                PracticeSessionViewModel(
                    pressDetectionService: PressDetectionService(),
                    chordAttemptAccumulator: ChordAttemptAccumulator(),
                    sleeper: TaskSleeper()
                )
            }
        )
    }
}
