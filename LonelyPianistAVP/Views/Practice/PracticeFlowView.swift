import SwiftUI

struct PracticeFlowView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 0) {
            PracticeStepView(
                viewModel: viewModel,
                onBackToLibrary: { router.goToLibrary() },
                onRestartFromTypePicker: { router.exitToTypePicker(reason: "user restarted from practice") }
            )
        }
        .frame(minWidth: 1200, idealWidth: 1600, minHeight: 520, idealHeight: 620)
    }
}
