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
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowIDs.preparation, context: context)
        }

        Window("Library", id: WindowIDs.library) {
            LibraryWindowRootView(appState: appState, services: services, flowState: flowState)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowIDs.library, context: context)
        }

        Window("Practice", id: WindowIDs.practice) {
            PracticeWindowRootView(viewModel: arGuideViewModel)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowIDs.practice, context: context)
        }

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

    private func makeReplacementPlacementIfPossible(
        targetWindowID: String,
        context: WindowPlacementContext
    ) -> WindowPlacement {
        guard let pendingTransition = coordinator.pendingTransition else { return WindowPlacement() }
        guard pendingTransition.toWindowID == targetWindowID else { return WindowPlacement() }

        guard let sourceWindow = context.windows.first(where: { $0.id == pendingTransition.fromWindowID }) else {
            return WindowPlacement()
        }

        return WindowPlacement(.replacing(sourceWindow))
    }
}
