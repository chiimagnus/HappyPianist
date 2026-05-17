import SwiftUI

@main
struct LonelyPianistAVPApp: App {
    @State private var appState: AppState
    @State private var services: AppServices
    @State private var arGuideViewModel: ARGuideViewModel
    @State private var flowState: FlowState
    @State private var coordinator: WindowCoordinator

    init() {
        let root = AppCompositionRoot()
        _appState = State(initialValue: root.appState)
        _services = State(initialValue: root.services)
        _arGuideViewModel = State(initialValue: root.arGuideViewModel)
        _flowState = State(initialValue: root.flowState)
        _coordinator = State(initialValue: WindowCoordinator(
            flowState: root.flowState,
            pianoModeRegistry: root.services.pianoModeRegistry
        ))
    }

    var body: some Scene {
        Window("Preparation", id: WindowIDs.preparation) {
            PreparationWindowRootView(arGuideViewModel: arGuideViewModel)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        Window("Library", id: WindowIDs.library) {
            LibraryWindowRootView(appState: appState, services: services, flowState: flowState)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)

        Window("Practice", id: WindowIDs.practice) {
            PracticeWindowRootView(viewModel: arGuideViewModel)
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
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
