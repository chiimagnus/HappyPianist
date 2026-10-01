import Foundation

@MainActor
final class ImmersiveSpacePresentationCoordinator {
    typealias ModeTransitionHandler =
        @MainActor (AppState.ImmersiveMode, AppState.ImmersiveMode) -> Void

    private let appState: AppState
    private var modeTransitionHandler: ModeTransitionHandler?
    private var operationTail: Task<Void, Never>?
    private var operationTailID: UUID?
    private var pendingOpenMode: AppState.ImmersiveMode?
    private var isDismissRequested = false
    private var deferredDismissHandler: ImmersiveSpaceDismissHandler?

    init(appState: AppState) {
        self.appState = appState
    }

    func installModeTransitionHandler(_ handler: @escaping ModeTransitionHandler) {
        modeTransitionHandler = handler
    }

    func open(
        mode: AppState.ImmersiveMode,
        using openImmersiveSpace: @escaping ImmersiveSpaceOpenHandler
    ) async -> String? {
        await enqueue { [weak self] in
            guard let self else { return "沉浸空间控制器已释放，请重试。" }
            return await performOpen(mode: mode, using: openImmersiveSpace)
        }
    }

    func close(using dismissImmersiveSpace: @escaping ImmersiveSpaceDismissHandler) async {
        await enqueue { [weak self] in
            guard let self else { return }

            if appState.immersiveSpaceState == .open {
                guard isDismissRequested == false else { return }
                isDismissRequested = true
                await dismissImmersiveSpace()
                return
            }

            guard pendingOpenMode != nil else { return }
            deferredDismissHandler = dismissImmersiveSpace
        }
    }

    func sceneDidAppear() {
        appState.immersiveSpaceState = .open
        pendingOpenMode = nil

        guard let deferredDismissHandler else { return }
        self.deferredDismissHandler = nil
        Task { @MainActor [weak self] in
            await self?.close(using: deferredDismissHandler)
        }
    }

    func sceneDidDisappear() {
        appState.immersiveSpaceState = .closed
        pendingOpenMode = nil
        isDismissRequested = false
        deferredDismissHandler = nil
    }

    private func performOpen(
        mode: AppState.ImmersiveMode,
        using openImmersiveSpace: @escaping ImmersiveSpaceOpenHandler
    ) async -> String? {
        let previousMode = appState.immersiveMode

        if appState.immersiveSpaceState == .open {
            guard previousMode != mode else { return nil }
            appState.immersiveMode = mode
            modeTransitionHandler?(previousMode, mode)
            return nil
        }

        if pendingOpenMode != nil {
            pendingOpenMode = mode
            appState.immersiveMode = mode
            return nil
        }

        pendingOpenMode = mode
        appState.immersiveMode = mode
        let result = await openImmersiveSpace(appState.immersiveSpaceID)

        if appState.immersiveSpaceState == .open {
            pendingOpenMode = nil
            return nil
        }

        switch result {
        case .opened:
            return nil
        case .userCancelled:
            pendingOpenMode = nil
            deferredDismissHandler = nil
            appState.immersiveMode = previousMode
            return "已取消打开沉浸空间。"
        case .error:
            pendingOpenMode = nil
            deferredDismissHandler = nil
            appState.immersiveMode = previousMode
            return "打开沉浸空间失败，请重试。"
        case .unknown:
            pendingOpenMode = nil
            deferredDismissHandler = nil
            appState.immersiveMode = previousMode
            return "沉浸空间返回未知状态，请重试。"
        }
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async -> Result
    ) async -> Result {
        let previous = operationTail
        let resultTask = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        let operationID = UUID()
        operationTailID = operationID
        operationTail = Task { @MainActor [weak self] in
            _ = await resultTask.value
            guard let self, operationTailID == operationID else { return }
            operationTail = nil
            operationTailID = nil
        }
        return await resultTask.value
    }
}
