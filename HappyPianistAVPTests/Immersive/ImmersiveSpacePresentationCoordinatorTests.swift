@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func immersiveCoordinatorRestoresModeWhenOpenIsCancelledBeforeMount() async {
    let appState = AppState()
    appState.immersiveMode = .library
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)

    let message = await coordinator.open(mode: .practice) { _ in
        #expect(appState.immersiveMode == .practice)
        #expect(appState.immersiveSpaceState == .closed)
        return .userCancelled
    }

    #expect(message == "已取消打开沉浸空间。")
    #expect(appState.immersiveMode == .library)
    #expect(appState.immersiveSpaceState == .closed)
}

@Test
@MainActor
func immersiveCoordinatorRestoresModeWhenOpenFailsBeforeMount() async {
    let appState = AppState()
    appState.immersiveMode = .library
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)

    let message = await coordinator.open(mode: .calibration) { _ in .error }

    #expect(message == "打开沉浸空间失败，请重试。")
    #expect(appState.immersiveMode == .library)
    #expect(appState.immersiveSpaceState == .closed)
}

@Test
@MainActor
func immersiveCoordinatorTreatsMountedSceneAsTruthWhenOpenResultArrivesLate() async {
    let appState = AppState()
    appState.immersiveMode = .library
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)

    let message = await coordinator.open(mode: .calibration) { _ in
        coordinator.sceneDidAppear()
        return .userCancelled
    }

    #expect(message == nil)
    #expect(appState.immersiveMode == .calibration)
    #expect(appState.immersiveSpaceState == .open)
}

@Test
@MainActor
func immersiveCoordinatorSwitchesMountedModeWithoutOpeningAgain() async {
    let appState = AppState()
    appState.immersiveMode = .library
    appState.immersiveSpaceState = .open
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)
    var transitions: [(AppState.ImmersiveMode, AppState.ImmersiveMode)] = []
    var openCount = 0
    coordinator.installModeTransitionHandler { oldMode, newMode in
        transitions.append((oldMode, newMode))
    }

    let message = await coordinator.open(mode: .practice) { _ in
        openCount += 1
        return .opened
    }

    #expect(message == nil)
    #expect(openCount == 0)
    #expect(appState.immersiveMode == .practice)
    #expect(transitions.count == 1)
    #expect(transitions.first?.0 == .library)
    #expect(transitions.first?.1 == .practice)
}

@Test
@MainActor
func immersiveCoordinatorCoalescesOpenWhileSceneMountIsPending() async {
    let appState = AppState()
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)
    var openCount = 0

    #expect(await coordinator.open(mode: .calibration) { _ in
        openCount += 1
        return .opened
    } == nil)

    #expect(appState.immersiveSpaceState == .closed)

    #expect(await coordinator.open(mode: .practice) { _ in
        openCount += 1
        return .opened
    } == nil)

    #expect(openCount == 1)
    #expect(appState.immersiveMode == .practice)
}

@Test
@MainActor
func immersiveCoordinatorDefersCloseUntilPendingOpenActuallyMounts() async {
    let appState = AppState()
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)
    var dismissCount = 0

    #expect(await coordinator.open(mode: .practice) { _ in .opened } == nil)
    await coordinator.close {
        dismissCount += 1
    }
    #expect(dismissCount == 0)

    coordinator.sceneDidAppear()
    for _ in 0 ..< 4 {
        await Task.yield()
    }

    #expect(dismissCount == 1)
    #expect(appState.immersiveSpaceState == .open)

    coordinator.sceneDidDisappear()
    #expect(appState.immersiveSpaceState == .closed)
}

@Test
@MainActor
func immersiveCoordinatorCoalescesRepeatedCloseUntilSceneDisappears() async {
    let appState = AppState()
    appState.immersiveSpaceState = .open
    let coordinator = ImmersiveSpacePresentationCoordinator(appState: appState)
    var dismissCount = 0

    await coordinator.close { dismissCount += 1 }
    await coordinator.close { dismissCount += 1 }

    #expect(dismissCount == 1)
    #expect(appState.immersiveSpaceState == .open)

    coordinator.sceneDidDisappear()
    appState.immersiveSpaceState = .open
    await coordinator.close { dismissCount += 1 }
    #expect(dismissCount == 2)
}
