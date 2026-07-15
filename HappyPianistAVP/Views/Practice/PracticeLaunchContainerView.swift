import SwiftUI

struct PracticeLaunchContainerView: View {
    @Bindable var launchViewModel: PracticeLaunchViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel
    let onReturn: @MainActor () -> Void

    var body: some View {
        Group {
            switch launchViewModel.state {
            case .noRequest:
                EmptyView()
            case .requested, .loading:
                ProgressView("正在准备练习…")
                    .controlSize(.large)
            case let .failure(failure):
                PracticeLaunchFailureView(
                    failure: failure,
                    onRetry: {
                        Task { @MainActor in
                            await launchViewModel.retry()
                        }
                    },
                    onReturn: onReturn
                )
            case .ready:
                PracticeStepView(
                    viewModel: arGuideViewModel,
                    onBackToLibrary: onReturn
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
