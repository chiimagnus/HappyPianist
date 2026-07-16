import SwiftUI

struct PreparationWindowRootView: View {
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Environment(WindowTransitionState.self) private var windowState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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
                guard windowState.pendingTransition == nil else { return }
                windowState.beginTransition(from: .preparation, to: .library)
                Task { @MainActor in
                    let dismissHandler = makePracticeImmersiveDismissHandler(dismissImmersiveSpace)
                    await arGuideViewModel.closeImmersiveForStep(
                        dismissImmersiveSpace: dismissHandler
                    )
                    await arGuideViewModel.recoverImmersiveStateIfStuck()
                    openWindow(id: WindowID.library)
                }
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
