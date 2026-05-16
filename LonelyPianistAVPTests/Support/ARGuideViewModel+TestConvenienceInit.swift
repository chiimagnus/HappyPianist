@testable import LonelyPianistAVP

extension ARGuideViewModel {
    @MainActor
    convenience init(appState: AppState, flowState: FlowState) {
        let registry = PianoModeRegistryService(modes: [])
        let factory = PracticeSessionViewModelFactoryService(
            pianoModeRegistry: registry,
            makeFallbackPracticeSessionViewModel: {
                PracticeSessionViewModel(
                    pressDetectionService: PressDetectionService(),
                    chordAttemptAccumulator: ChordAttemptAccumulator(),
                    sleeper: TaskSleeper()
                )
            }
        )
        self.init(
            appState: appState,
            flowState: flowState,
            pianoModeRegistry: registry,
            practiceSessionViewModelFactory: factory
        )
    }
}

