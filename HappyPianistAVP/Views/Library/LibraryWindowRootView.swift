import SwiftUI

struct LibraryWindowRootView: View {
    @Environment(WindowTransitionState.self) private var windowState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var appState: AppState
    @State private var songLibraryViewModel: SongLibraryViewModel

    init(appState: AppState, songLibraryViewModel: SongLibraryViewModel) {
        _appState = Bindable(wrappedValue: appState)
        _songLibraryViewModel = State(initialValue: songLibraryViewModel)
    }

    var body: some View {
        LibraryContentView(
            songLibraryViewModel: songLibraryViewModel,
            onBackToPreparation: {
                windowState.resetToPreparation(reason: "user tapped back from library window")
                windowState.beginTransition(from: .library, to: .preparation)
                openWindow(id: WindowID.preparation)
            },
            onStartPractice: {
                windowState.beginTransition(from: .library, to: .practice)
                openWindow(id: WindowID.practice)
            }
        )
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            dismissPendingSourceIfNeeded()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = windowState.consumePendingTransition(to: .library) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }
}
