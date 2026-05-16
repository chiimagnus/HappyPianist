import SwiftUI

@main
struct LonelyPianistAVPApp: App {
    @State private var appState: AppState
    @State private var services: AppServices
    @State private var arGuideViewModel: ARGuideViewModel
    @State private var flowState: FlowState
    @State private var router: AppRouter
    @State private var coordinator: WindowCoordinator
    @AppStorage("immersivePanoramaEnabled") private var immersivePanoramaEnabled = false

    init() {
        let root = AppCompositionRoot()
        _appState = State(initialValue: root.appState)
        _services = State(initialValue: root.services)
        _arGuideViewModel = State(initialValue: root.arGuideViewModel)
        _flowState = State(initialValue: root.flowState)
        _router = State(initialValue: root.router)
        _coordinator = State(initialValue: WindowCoordinator(flowState: root.flowState, pianoModeRegistry: root.services.pianoModeRegistry))
    }

    var body: some Scene {
        let progressiveImmersionStyle: ImmersionStyle = .progressive(0.0...1.0, initialAmount: 0.7, aspectRatio: nil)
        let selectedImmersionStyle: any ImmersionStyle = immersivePanoramaEnabled ? progressiveImmersionStyle : .mixed

        WindowGroup(id: WindowIDs.preparation) {
            PreparationWindowRootView(
                services: services,
                arGuideViewModel: arGuideViewModel,
                router: router
            )
            .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        WindowGroup(id: WindowIDs.library) {
            LibraryWindowRootView(appState: appState, services: services, flowState: flowState)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        WindowGroup(id: WindowIDs.practice) {
            PracticeWindowRootView()
                .environment(coordinator)
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
        .immersionStyle(selection: .constant(selectedImmersionStyle), in: .mixed, progressiveImmersionStyle)
    }
}
