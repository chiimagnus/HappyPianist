import SwiftUI

@main
struct LonelyPianistAVPApp: App {
    @State private var appState: AppState
    @State private var homeViewModel: HomeViewModel
    @State private var arGuideViewModel: ARGuideViewModel
    @State private var songLibraryViewModel: SongLibraryViewModel

    init() {
        let appState = AppState()
        appState.loadStoredCalibrationIfPossible()

        _appState = State(initialValue: appState)
        _homeViewModel = State(initialValue: HomeViewModel(appState: appState))
        _arGuideViewModel = State(initialValue: ARGuideViewModel(appState: appState))
        _songLibraryViewModel = State(initialValue: SongLibraryViewModel(appState: appState))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                homeViewModel: homeViewModel,
                arGuideViewModel: arGuideViewModel,
                songLibraryViewModel: songLibraryViewModel
            )
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appState.immersiveSpaceID) {
            ImmersiveView(viewModel: arGuideViewModel)
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
