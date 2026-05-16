import SwiftUI

struct PracticeWindowRootView: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Bindable var viewModel: ARGuideViewModel

    init(viewModel: ARGuideViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    var body: some View {
        PracticeFlowView(
            viewModel: viewModel,
            onBackToLibrary: {
                coordinator.openLibrary(dismissCurrent: .practice, openWindow: openWindow, dismissWindow: dismissWindow)
            },
            onRestartFromTypePicker: {
                coordinator.resetToPreparation(reason: "user restarted from practice window")
                coordinator.openPreparation(dismissCurrent: .practice, openWindow: openWindow, dismissWindow: dismissWindow)
            }
        )
        .frame(minWidth: 1200, idealWidth: 1600, minHeight: 520, idealHeight: 620)
    }
}
