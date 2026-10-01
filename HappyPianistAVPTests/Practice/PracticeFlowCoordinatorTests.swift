import Foundation
import Practice
import MusicXML
import Diagnostics
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func enterPracticeStepCallsOpenImmersive() async {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)

    viewModel.setPracticeVirtualPianoEnabled(true)
    practiceSetupState.setImportedSteps(from: makeTestPreparedPractice())

    var openedIDs: [String] = []
    await viewModel.enterPracticeStep(
        openImmersiveSpace: { id in
            openedIDs.append(id)
            return .opened
        },
        dismissImmersiveSpace: {}
    )

    #expect(openedIDs.count == 1)
}

@Test
@MainActor
func closeImmersiveCallsDismissWhenMounted() async {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
    appState.immersiveSpaceState = .open

    var dismissCount = 0
    await viewModel.closeImmersive(using: { dismissCount += 1 })

    #expect(dismissCount == 1)
    #expect(appState.immersiveSpaceState == .open)
}

@Test
@MainActor
func closeImmersiveDoesNotDismissWhenAlreadyClosed() async {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
    appState.immersiveSpaceState = .closed

    var dismissCount = 0
    await viewModel.closeImmersive(using: { dismissCount += 1 })

    #expect(dismissCount == 0)
}
