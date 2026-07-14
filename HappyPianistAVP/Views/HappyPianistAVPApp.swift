import SwiftUI

@main
struct HappyPianistAVPApp: App {
    @State private var appState: AppState
    private let graph: LiveAppGraph

    init() {
        let graph = LiveAppGraph.make()
        self.graph = graph
        _appState = State(initialValue: graph.appState)
    }

    var body: some Scene {
        Window("Preparation", id: WindowID.preparation) {
            PreparationWindowRootView(arGuideViewModel: graph.arGuideViewModel)
                .environment(graph.windowState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        Window("Library", id: WindowID.library) {
            LibraryWindowRootView(
                appState: appState,
                songLibraryViewModel: graph.songLibraryViewModel,
                practiceLaunchViewModel: graph.practiceLaunchViewModel,
                diagnosticsViewModel: graph.diagnosticsViewModel
            )
            .environment(graph.windowState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        Window("Practice", id: WindowID.practice) {
            PracticeWindowRootView(
                arGuideViewModel: graph.arGuideViewModel,
                launchViewModel: graph.practiceLaunchViewModel
            )
                .environment(graph.windowState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appState.immersiveSpaceID) {
            ImmersiveView(viewModel: graph.arGuideViewModel)
                .onAppear {
                    appState.immersiveSpaceState = .open
                }
                .onDisappear {
                    appState.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

}
