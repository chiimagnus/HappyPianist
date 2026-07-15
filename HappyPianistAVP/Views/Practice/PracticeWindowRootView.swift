import SwiftUI

struct PracticeWindowRootView: View {
    @Environment(WindowTransitionState.self) private var windowState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var arGuideViewModel: ARGuideViewModel
    @Bindable var launchViewModel: PracticeLaunchViewModel
    @State private var sceneLifecycleCoordinator = PracticeSceneLifecycleCoordinator()
    @State private var returnCoordinator = PracticeWindowReturnCoordinator()
    @State private var immersiveCloseCoordinator = PracticeImmersiveCloseCoordinator()
    @State private var systemCloseCoordinator = PracticeSystemCloseCoordinator()
    @State private var isReturnSaveFailurePresented = false
    @State private var isDiscardConfirmationPresented = false

    init(
        arGuideViewModel: ARGuideViewModel,
        launchViewModel: PracticeLaunchViewModel
    ) {
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
        _launchViewModel = Bindable(wrappedValue: launchViewModel)
    }

    var body: some View {
        PracticeLaunchContainerView(
            launchViewModel: launchViewModel,
            arGuideViewModel: arGuideViewModel,
            onReturn: beginReturnToLibrary
        )
        .task(id: launchViewModel.activationIdentity) {
            guard scenePhase == .active else { return }
            dismissPendingSourceIfNeeded()
            await activateCurrentRequest()
        }
        .onChange(of: scenePhase) {
            handleScenePhaseChange()
        }
        .onAppear {
            dismissPendingSourceIfNeeded()
        }
        .onDisappear {
            closeForSystemDisappear()
        }
        .alert("无法保存练习记录", isPresented: $isReturnSaveFailurePresented) {
            Button("重试") { beginReturnToLibrary() }
            Button("放弃未保存增量", role: .destructive) {
                isDiscardConfirmationPresented = true
            }
            Button("留在练习", role: .cancel) {}
        } message: {
            Text("Practice 会保持打开。你可以重试，或明确放弃尚未成功写入的增量。")
        }
        .confirmationDialog(
            "放弃未保存增量并返回选曲库？",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("放弃并返回", role: .destructive) {
                beginDiscardingReturnToLibrary()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已经成功保存的 checkpoint 会保留；只有仍在内存中、尚未写入的增量会被放弃。")
        }
    }

    private func dismissPendingSourceIfNeeded() {
        guard let transition = windowState.consumePendingTransition(to: .practice) else { return }
        withTransaction(\.dismissBehavior, .destructive) {
            dismissWindow(id: transition.fromWindowID)
        }
    }

    private func handleScenePhaseChange() {
        let phase = scenePhase
        sceneLifecycleCoordinator.schedule { @MainActor in
            guard returnCoordinator.isReturning == false else { return }
            if phase == .active {
                dismissPendingSourceIfNeeded()
                await activateCurrentRequest()
            } else {
                await launchViewModel.suspendForInactiveScene()
            }
        }
    }

    private func beginReturnToLibrary() {
        beginReturnToLibrary(discardingUnsavedChanges: false)
    }

    private func beginDiscardingReturnToLibrary() {
        beginReturnToLibrary(discardingUnsavedChanges: true)
    }

    private func beginReturnToLibrary(discardingUnsavedChanges: Bool) {
        let pendingLifecycle = sceneLifecycleCoordinator.cancel()
        returnCoordinator.begin(
            beginReturn: launchViewModel.beginReturn,
            leave: {
                await pendingLifecycle?.value
                if discardingUnsavedChanges {
                    await arGuideViewModel.discardUnsavedProgressAndLeavePracticeStep()
                    return .saved
                }
                return await arGuideViewModel.leavePracticeStep()
            },
            closeImmersive: {
                await closeImmersivePresentationIfNeeded()
            },
            recoverImmersive: {},
            abortReturn: launchViewModel.abortReturn,
            finishReturn: { operationID in
                if discardingUnsavedChanges {
                    return await launchViewModel.discardUnsavedChangesAndFinishReturn(
                        operationID: operationID
                    )
                }
                return await launchViewModel.finishReturn(operationID: operationID)
            },
            onFailure: {
                isReturnSaveFailurePresented = true
            },
            navigate: {
                windowState.beginTransition(from: .practice, to: .library)
                openWindow(id: WindowID.library)
            }
        )
    }

    private func closeForSystemDisappear() {
        let pendingLifecycle = sceneLifecycleCoordinator.cancel()
        systemCloseCoordinator.begin {
            await pendingLifecycle?.value
            await closeImmersivePresentationIfNeeded()
            await arGuideViewModel.closePracticeStepForSystemDisappear()
            await launchViewModel.closeForSystemDisappear()
        }
    }

    private func activateCurrentRequest() async {
        await closeImmersivePresentationIfNeeded()
        await launchViewModel.activateCurrentRequest()
    }

    private func closeImmersivePresentationIfNeeded() async {
        await immersiveCloseCoordinator.closeIfNeeded(
            isClosed: arGuideViewModel.immersiveSpaceState == .closed,
            close: {
                let dismissHandler = makePracticeImmersiveDismissHandler(dismissImmersiveSpace)
                await arGuideViewModel.closeImmersiveForStep(
                    dismissImmersiveSpace: dismissHandler
                )
            },
            recover: arGuideViewModel.recoverImmersiveStateIfStuck
        )
    }
}

@MainActor
final class PracticeSceneLifecycleCoordinator {
    private var operationTask: Task<Void, Never>?

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        let previousTask = operationTask
        previousTask?.cancel()
        operationTask = Task { @MainActor in
            await previousTask?.value
            guard Task.isCancelled == false else { return }
            await operation()
        }
    }

    func cancel() -> Task<Void, Never>? {
        let pendingTask = operationTask
        pendingTask?.cancel()
        operationTask = nil
        return pendingTask
    }

    func waitForCurrentOperation() async {
        await operationTask?.value
    }
}

@MainActor
final class PracticeImmersiveCloseCoordinator {
    private var operationTask: Task<Void, Never>?

    func closeIfNeeded(
        isClosed: Bool,
        close: @escaping @MainActor () async -> Void,
        recover: @escaping @MainActor () async -> Void
    ) async {
        if let operationTask {
            await operationTask.value
            return
        }
        guard isClosed == false else { return }
        let task = Task { @MainActor in
            await close()
            await recover()
        }
        operationTask = task
        await task.value
        operationTask = nil
    }
}

@MainActor
final class PracticeWindowReturnCoordinator {
    private var operationTask: Task<Void, Never>?

    var isReturning: Bool { operationTask != nil }

    func begin(
        beginReturn: @escaping @MainActor () -> UUID,
        leave: @escaping @MainActor () async -> PracticeProgressSaveStatus,
        closeImmersive: @escaping @MainActor () async -> Void,
        recoverImmersive: @escaping @MainActor () async -> Void,
        abortReturn: @escaping @MainActor (UUID) -> Void,
        finishReturn: @escaping @MainActor (UUID) async -> PracticeProgressSaveStatus,
        onFailure: @escaping @MainActor () -> Void = {},
        navigate: @escaping @MainActor () -> Void
    ) {
        guard operationTask == nil else { return }
        let operationID = beginReturn()
        operationTask = Task { @MainActor [weak self] in
            let leaveStatus = await leave()
            if case .failed = leaveStatus {
                abortReturn(operationID)
                self?.operationTask = nil
                onFailure()
                return
            }
            await closeImmersive()
            await recoverImmersive()
            let finishStatus = await finishReturn(operationID)
            if case .failed = finishStatus {
                abortReturn(operationID)
                self?.operationTask = nil
                onFailure()
                return
            }
            navigate()
        }
    }

    func waitForCompletion() async {
        await operationTask?.value
    }
}

@MainActor
final class PracticeSystemCloseCoordinator {
    private var operationTask: Task<Void, Never>?

    func begin(_ operation: @escaping @MainActor () async -> Void) {
        guard operationTask == nil else { return }
        operationTask = Task { @MainActor in
            await operation()
        }
    }

    func waitForCompletion() async {
        await operationTask?.value
    }
}
