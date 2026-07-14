import SwiftUI

struct PracticeLaunchContainerView: View {
    @Bindable var launchViewModel: PracticeLaunchViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel
    let onReturn: @MainActor () -> Void

    var body: some View {
        Group {
            switch launchViewModel.state {
            case .noRequest:
                ContentUnavailableView(
                    "尚未选择练习曲目",
                    systemImage: "music.note.list",
                    description: Text("请返回选曲库并选择一首曲目。")
                )
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
