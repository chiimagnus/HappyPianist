import SwiftUI

@main
struct LonelyPianistAVPApp: App {
    @State private var appState: AppState
    @State private var services: AppServices
    @State private var arGuideViewModel: ARGuideViewModel
    @AppStorage("immersivePanoramaEnabled") private var immersivePanoramaEnabled = false

    init() {
        let root = AppCompositionRoot()
        _appState = State(initialValue: root.appState)
        _services = State(initialValue: root.services)
        _arGuideViewModel = State(initialValue: root.arGuideViewModel)
    }

    var body: some Scene {
        let progressiveImmersionStyle: ImmersionStyle = .progressive(0.0...1.0, initialAmount: 0.7, aspectRatio: nil)
        let selectedImmersionStyle: any ImmersionStyle = immersivePanoramaEnabled ? progressiveImmersionStyle : .mixed

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
        .immersionStyle(selection: .constant(selectedImmersionStyle), in: .mixed, progressiveImmersionStyle)
    }
}
