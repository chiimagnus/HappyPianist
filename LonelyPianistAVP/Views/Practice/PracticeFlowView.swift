import SwiftUI

struct PracticeFlowView: View {
    @Bindable var viewModel: ARGuideViewModel
    let onBackToLibrary: @MainActor () -> Void
    let onRestartFromTypePicker: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PracticeStepView(
                viewModel: viewModel,
                onBackToLibrary: { onBackToLibrary() },
                onRestartFromTypePicker: { onRestartFromTypePicker() }
            )
        }
    }
}
