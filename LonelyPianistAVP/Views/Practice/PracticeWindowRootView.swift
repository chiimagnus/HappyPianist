import SwiftUI

struct PracticeWindowRootView: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var viewModel: ARGuideViewModel

    init(viewModel: ARGuideViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    var body: some View {
        PracticeFlowView(
            viewModel: viewModel,
            onBackToLibrary: {
                coordinator.beginTransition(from: .practice, to: .library)
                openWindow(id: WindowIDs.library)
            },
            onRestartFromTypePicker: {
                coordinator.resetToPreparation(reason: "user restarted from practice window")
                coordinator.beginTransition(from: .practice, to: .preparation)
                openWindow(id: WindowIDs.preparation)
            }
        )
        .frame(minWidth: 1200, idealWidth: 1600, minHeight: 520, idealHeight: 620)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            dismissPendingSourceIfNeeded()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = coordinator.consumePendingTransition(to: .practice) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }
}
