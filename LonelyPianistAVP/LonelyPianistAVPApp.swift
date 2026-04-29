import SwiftUI

@main
struct LonelyPianistAVPApp: App {
    @State private var appState: AppState
    @State private var services: AppServices
    @State private var arGuideViewModel: ARGuideViewModel

    init() {
        let appState = AppState()
        appState.loadStoredCalibrationIfPossible()
        let services = AppServices()

        _appState = State(initialValue: appState)
        _services = State(initialValue: services)
        _arGuideViewModel = State(initialValue: ARGuideViewModel(appState: appState))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                appState: appState,
                services: services,
                arGuideViewModel: arGuideViewModel
            )
            .environment(appState)
            .environment(services)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appState.immersiveSpaceID) {
            ImmersiveView(viewModel: arGuideViewModel)
                .environment(appState)
                .environment(services)
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
