import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(WindowTransitionState.self) private var windowState
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
                windowState.resetToPreparation(reason: "user tapped back from preparation")
            },
            nextToLibrary: {
                windowState.beginTransition(from: .preparation, to: .library)
                openWindow(id: WindowID.library)
            }
        )

        Group {
            if let selectedMode = windowState.pianoModeRegistry.mode(for: windowState.practiceSetupState.selectedPianoModeID) {
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
        guard let transition = windowState.consumePendingTransition(to: .preparation) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }
}
