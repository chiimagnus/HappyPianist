import SwiftUI

struct AppRootView: View {
    @Bindable var appState: AppState
    @Bindable var arGuideViewModel: ARGuideViewModel
    @State private var songLibraryViewModel: SongLibraryViewModel
    let router: AppRouter

    init(appState: AppState, services: AppServices, arGuideViewModel: ARGuideViewModel, router: AppRouter) {
        _appState = Bindable(wrappedValue: appState)
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        _songLibraryViewModel = State(initialValue: SongLibraryViewModel(
            appState: appState,
            flowState: router.flowState,
            practicePreparationService: services.practicePreparationService,
            indexStore: services.songLibraryIndexStore,
            fileStore: services.songFileStore,
            audioImportService: services.audioImportService,
            paths: services.songLibraryPaths,
            bundledProvider: services.bundledSongLibraryProvider,
            audioPlayer: services.songAudioPlayer
        ))
        self.router = router
    }

    var body: some View {
        @Bindable var router = router

        switch router.route {
        case .typePicker:
            PianoTypePickerView()
        case .preparation:
            if let mode = router.selectedPianoMode {
                mode.makePreparationView(arGuideViewModel: arGuideViewModel)
            } else {
                PianoTypePickerView()
            }
        case .library:
            LibraryFlowView(
                songLibraryViewModel: songLibraryViewModel,
                selectedPianoModeTitle: router.selectedPianoMode?.pickerCard.title,
                onBackToPreparation: {
                    router.exitToTypePicker(reason: "user tapped back from library (legacy AppRootView)")
                },
                onStartPractice: {
                    router.goToPractice()
                }
            )
        case .practice:
            PracticeFlowView(viewModel: arGuideViewModel)
        }
    }
}
