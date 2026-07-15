import SwiftUI

struct PracticeLaunchContainerView: View {
    @Bindable var launchViewModel: PracticeLaunchViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel
    let onReturn: @MainActor () -> Void

    var body: some View {
        Group {
            if let state = launchViewModel.state {
                switch state {
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
                        canRecoverCorruptedProgress: failure.recoveryAction == .backupAndResetCorruptedProgress,
                        onRecoverCorruptedProgress: {
                            Task { @MainActor in
                                await launchViewModel.recoverCorruptedProgress()
                            }
                        },
                        onReturn: onReturn
                    )
                case .ready:
                    PracticeStepView(
                        viewModel: arGuideViewModel,
                        onBackToLibrary: onReturn
                    )
                    .overlay(alignment: .top) {
                        if let failure = launchViewModel.progressAccessFailure {
                            PracticeProgressAccessFailureBanner(
                                failure: failure,
                                onRetry: {
                                    Task { @MainActor in
                                        await launchViewModel.retry()
                                    }
                                },
                                onRecoverCorruptedProgress: {
                                    Task { @MainActor in
                                        await launchViewModel.recoverCorruptedProgress()
                                    }
                                }
                            )
                            .padding()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
