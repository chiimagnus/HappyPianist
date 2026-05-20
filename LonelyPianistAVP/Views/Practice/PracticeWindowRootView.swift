import SwiftUI

struct PracticeWindowRootView: View {
    @Environment(WindowTransitionState.self) private var windowState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var viewModel: ARGuideViewModel

    init(viewModel: ARGuideViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    var body: some View {
        PracticeStepView(
            viewModel: viewModel,
            onBackToLibrary: {
                windowState.beginTransition(from: .practice, to: .library)
                openWindow(id: WindowID.library)
            },
            onRestartFromTypePicker: {
                windowState.resetToPreparation(reason: "user restarted from practice window")
                windowState.beginTransition(from: .practice, to: .preparation)
                openWindow(id: WindowID.preparation)
            }
        )
        // .frame(minWidth: 1200, idealWidth: 1600, minHeight: 520, idealHeight: 620)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            dismissPendingSourceIfNeeded()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = windowState.consumePendingTransition(to: .practice) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }
}
