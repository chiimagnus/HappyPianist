import SwiftUI

@main
struct HappyPianistAVPApp: App {
    @State private var appState: AppState

    init() {
        let appState = AppState()
        appState.configureLiveAppGraphIfNeeded()
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        Window("Preparation", id: WindowID.preparation) {
            PreparationWindowRootView(arGuideViewModel: appState.arGuideViewModel)
                .environment(appState.windowState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowID.preparation, context: context)
        }

        Window("Library", id: WindowID.library) {
            LibraryWindowRootView(
                appState: appState,
                songLibraryViewModel: appState.songLibraryViewModel,
                diagnosticsViewModel: appState.diagnosticsViewModel
            )
                .environment(appState.windowState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowID.library, context: context)
        }

        Window("Practice", id: WindowID.practice) {
            PracticeWindowRootView(viewModel: appState.arGuideViewModel)
                .environment(appState.windowState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowID.practice, context: context)
        }

        ImmersiveSpace(id: appState.immersiveSpaceID) {
            ImmersiveView(viewModel: appState.arGuideViewModel)
                .onAppear {
                    appState.immersiveSpaceState = .open
                }
                .onDisappear {
                    appState.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    private func makeReplacementPlacementIfPossible(
        targetWindowID: String,
        context: WindowPlacementContext
    ) -> WindowPlacement {
        guard let pendingTransition = appState.windowState.pendingTransition else { return WindowPlacement() }
        guard pendingTransition.toWindowID == targetWindowID else { return WindowPlacement() }

        guard let sourceWindow = context.windows.first(where: { $0.id == pendingTransition.fromWindowID }) else {
            return WindowPlacement()
        }

        return WindowPlacement(.replacing(sourceWindow))
    }
}
