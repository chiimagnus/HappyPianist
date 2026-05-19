import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func enterPracticeStepForwardsImmersiveHandlers() async {
    var openedIDs: [String] = []
    var dismissCount = 0

    let coordinator = PracticeFlowCoordinator(
        openImmersiveSpace: { id in
            openedIDs.append(id)
            return .opened
        },
        dismissImmersiveSpace: {
            dismissCount += 1
        }
    )

    let viewModel = CapturingPracticeFlowViewModel()
    await coordinator.enterPracticeStep(viewModel: viewModel)

    #expect(viewModel.enterPracticeStepCallCount == 1)
    #expect(openedIDs == ["enterPracticeStep"])
    #expect(dismissCount == 1)
}

@Test
@MainActor
func closeImmersiveForStepForwardsDismissHandler() async {
    var dismissCount = 0
    let coordinator = PracticeFlowCoordinator(
        openImmersiveSpace: { _ in .opened },
        dismissImmersiveSpace: { dismissCount += 1 }
    )

    let viewModel = CapturingPracticeFlowViewModel()
    await coordinator.closeImmersiveForStep(viewModel: viewModel)

    #expect(viewModel.closeImmersiveCallCount == 1)
    #expect(dismissCount == 1)
}

@MainActor
private final class CapturingPracticeFlowViewModel: PracticeFlowViewModelProtocol {
    private(set) var enterPracticeStepCallCount = 0
    private(set) var retryPracticeLocalizationCallCount = 0
    private(set) var enterVirtualPianoPlacementCallCount = 0
    private(set) var openImmersiveForStepCallCount = 0
    private(set) var closeImmersiveCallCount = 0

    func enterPracticeStep(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler
    ) async {
        enterPracticeStepCallCount += 1
        _ = await openImmersiveSpace("enterPracticeStep")
        await dismissImmersiveSpace()
    }

    func retryPracticeLocalization(
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler,
        dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler
    ) async {
        retryPracticeLocalizationCallCount += 1
        _ = await openImmersiveSpace("retryPracticeLocalization")
        await dismissImmersiveSpace()
    }

    func enterVirtualPianoPlacement(openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler) async {
        enterVirtualPianoPlacementCallCount += 1
        _ = await openImmersiveSpace("enterVirtualPianoPlacement")
    }

    func openImmersiveForStep(
        mode _: AppState.ImmersiveMode,
        openImmersiveSpace: PracticeFlowOpenImmersiveSpaceHandler
    ) async -> String? {
        openImmersiveForStepCallCount += 1
        _ = await openImmersiveSpace("openImmersiveForStep")
        return nil
    }

    func closeImmersiveForStep(dismissImmersiveSpace: PracticeFlowDismissImmersiveSpaceHandler) async {
        closeImmersiveCallCount += 1
        await dismissImmersiveSpace()
    }
}

