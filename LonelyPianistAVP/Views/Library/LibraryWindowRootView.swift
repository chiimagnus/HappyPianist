import SwiftUI

struct LibraryWindowRootView: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Bindable var appState: AppState
    let services: AppServices
    let flowState: FlowState

    @State private var songLibraryViewModel: SongLibraryViewModel

    init(appState: AppState, services: AppServices, flowState: FlowState) {
        _appState = Bindable(wrappedValue: appState)
        self.services = services
        self.flowState = flowState
        _songLibraryViewModel = State(initialValue: SongLibraryViewModel(
            appState: appState,
            flowState: flowState,
            practicePreparationService: services.practicePreparationService,
            indexStore: services.songLibraryIndexStore,
            fileStore: services.songFileStore,
            audioImportService: services.audioImportService,
            paths: services.songLibraryPaths,
            bundledProvider: services.bundledSongLibraryProvider,
            audioPlayer: services.songAudioPlayer
        ))
    }

    var body: some View {
        let selectedTitle = coordinator.pianoModeRegistry
            .mode(for: coordinator.flowState.selectedPianoModeID)?
            .pickerCard.title

        LibraryFlowView(
            songLibraryViewModel: songLibraryViewModel,
            selectedPianoModeTitle: selectedTitle,
            onBackToPreparation: {
                coordinator.resetToPreparation(reason: "user tapped back from library window")
                coordinator.openPreparation(dismissCurrent: .library, openWindow: openWindow, dismissWindow: dismissWindow)
            },
            onStartPractice: {
                coordinator.openPractice(dismissCurrent: .library, openWindow: openWindow, dismissWindow: dismissWindow)
            }
        )
    }
}
