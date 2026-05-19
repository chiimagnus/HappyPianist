import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    init(
        arGuideViewModel: ARGuideViewModel
    ) {
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
    }

    var body: some View {
        let actions = PreparationNavigationActions(
            backToTypePicker: {
                coordinator.resetToPreparation(reason: "user tapped back from preparation")
            },
            nextToLibrary: {
                coordinator.beginTransition(from: .preparation, to: .library)
                openWindow(id: WindowIDs.library)
            }
        )

        Group {
            if let selectedMode = coordinator.pianoModeRegistry.mode(for: coordinator.flowState.selectedPianoModeID) {
                PianoModePreparationRouterView(
                    route: selectedMode.preparationRoute,
                    arGuideViewModel: arGuideViewModel
                )
            } else {
                PianoTypePickerView()
            }
        }
        .environment(\.preparationNavigationActions, actions)
        // .frame(minWidth: 860, idealWidth: 900, minHeight: 520, idealHeight: 650)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            dismissPendingSourceIfNeeded()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = coordinator.consumePendingTransition(to: .preparation) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }
}
