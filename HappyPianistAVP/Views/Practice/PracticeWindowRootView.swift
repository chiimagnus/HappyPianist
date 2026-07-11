import SwiftUI

struct PracticeWindowRootView: View {
    @Environment(WindowTransitionState.self) private var windowState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var viewModel: ARGuideViewModel
    @State private var sceneLifecycleTask: Task<Void, Never>?

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
            handleScenePhaseChange()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
        .onDisappear {
            sceneLifecycleTask?.cancel()
            sceneLifecycleTask = nil
            guard windowState.pendingTransition == nil else { return }
            Task { @MainActor in
                let dismissHandler = makePracticeImmersiveDismissHandler(dismissImmersiveSpace)
                await viewModel.leavePracticeStep()
                await viewModel.closeImmersiveForStep(dismissImmersiveSpace: dismissHandler)
                await viewModel.recoverImmersiveStateIfStuck()
                openWindow(id: WindowID.library)
            }
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = windowState.consumePendingTransition(to: .practice) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }

    private func handleScenePhaseChange() {
        sceneLifecycleTask?.cancel()
        let phase = scenePhase
        sceneLifecycleTask = Task { @MainActor in
            guard Task.isCancelled == false else { return }
            if phase == .active {
                viewModel.resumePracticeAfterSuspension()
                dismissPendingSourceIfNeeded()
            } else {
                await viewModel.suspendPracticeAndFlushProgress()
            }
        }
    }
}
