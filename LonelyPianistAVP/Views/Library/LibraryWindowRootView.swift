import SwiftUI

struct LibraryWindowRootView: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

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
                coordinator.beginTransition(from: .library, to: .preparation)
                openWindow(id: WindowIDs.preparation)
            },
            onStartPractice: {
                coordinator.beginTransition(from: .library, to: .practice)
                openWindow(id: WindowIDs.practice)
            }
        )
        // .frame(minWidth: 700, idealWidth: 900, minHeight: 520, idealHeight: 700)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            dismissPendingSourceIfNeeded()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = coordinator.consumePendingTransition(to: .library) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }
}
