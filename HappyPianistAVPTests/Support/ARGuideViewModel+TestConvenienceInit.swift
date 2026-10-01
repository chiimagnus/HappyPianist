import Practice
@testable import HappyPianistAVP

extension ARGuideViewModel {
    @MainActor
    convenience init(
        appState: AppState,
        practiceSetupState: PracticeSetupState,
        spatialLibraryViewModel: SpatialLibraryViewModel? = nil
    ) {
        let registry = PianoModeRegistryService(modes: [])
        self.init(
            appState: appState,
            spatialLibraryViewModel: spatialLibraryViewModel,
            practiceSetupState: practiceSetupState,
            pianoModeRegistry: registry,
            makePracticeSessionViewModel: { _ in
                PracticeSessionViewModel(
                    chordAttemptAccumulator: ChordAttemptAccumulator(),
                    sleeper: TaskSleeper()
                )
            }
        )
    }
}
