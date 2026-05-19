import SwiftUI

@MainActor
final class PracticeFlowCoordinator {
    private let openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    private let dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler

    init(
        openImmersiveSpace: @escaping PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) {
        self.openImmersiveSpace = openImmersiveSpace
        self.dismissImmersiveSpace = dismissImmersiveSpace
    }

    static func live(
        openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) -> PracticeFlowCoordinator {
        PracticeFlowCoordinator(
            openImmersiveSpace: { id in
                switch await openImmersiveSpace(id: id) {
                case .opened:
                    return .opened
                case .userCancelled:
                    return .userCancelled
                case .error:
                    return .error
                @unknown default:
                    return .unknown
                }
            },
            dismissImmersiveSpace: {
                await dismissImmersiveSpace()
            }
        )
    }

    func enterPracticeStep(viewModel: any PracticeFlowViewModelProtocol) async {
        await viewModel.enterPracticeStep(
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func retryPracticeLocalization(viewModel: any PracticeFlowViewModelProtocol) async {
        await viewModel.retryPracticeLocalization(
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func enterVirtualPianoPlacement(viewModel: any PracticeFlowViewModelProtocol) async {
        await viewModel.enterVirtualPianoPlacement(openImmersiveSpace: openImmersiveSpace)
    }

    func closeImmersiveForStep(viewModel: any PracticeFlowViewModelProtocol) async {
        await viewModel.closeImmersiveForStep(dismissImmersiveSpace: dismissImmersiveSpace)
    }

    func openImmersiveForStep(viewModel: any PracticeFlowViewModelProtocol, mode: AppState.ImmersiveMode) async -> String? {
        await viewModel.openImmersiveForStep(mode: mode, openImmersiveSpace: openImmersiveSpace)
    }
}

@MainActor
protocol PracticeFlowViewModelProtocol: AnyObject {
    func enterPracticeStep(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) async

    func retryPracticeLocalization(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: @escaping PracticeFlowDismissImmersiveSpaceHandler
    ) async

    func enterVirtualPianoPlacement(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    ) async

    func openImmersiveForStep(
        mode: AppState.ImmersiveMode,
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    ) async -> String?

    func closeImmersiveForStep(
        dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler
    ) async
}

extension ARGuideViewModel: PracticeFlowViewModelProtocol {}
