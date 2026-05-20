import Foundation
import Observation

@MainActor
@Observable
final class ARGuidePracticeViewModel {
    typealias PracticeLocalizationFailure = PracticeLocalizationViewModel.PracticeLocalizationFailure
    typealias PracticeLocalizationState = PracticeLocalizationViewModel.PracticeLocalizationState

    private let appState: AppState
    private let practiceSetupState: PracticeSetupState
    private let practiceLocalizationViewModel: PracticeLocalizationViewModel
    private let placementViewModel: VirtualPianoPlacementViewModel

    var practiceSessionViewModel: PracticeSessionViewModel

    init(
        appState: AppState,
        practiceSetupState: PracticeSetupState,
        practiceSessionViewModel: PracticeSessionViewModel,
        practiceLocalizationViewModel: PracticeLocalizationViewModel,
        placementViewModel: VirtualPianoPlacementViewModel
    ) {
        self.appState = appState
        self.practiceSetupState = practiceSetupState
        self.practiceSessionViewModel = practiceSessionViewModel
        self.practiceLocalizationViewModel = practiceLocalizationViewModel
        self.placementViewModel = placementViewModel
    }

    var practiceLocalizationState: PracticeLocalizationState {
        practiceLocalizationViewModel.practiceLocalizationState
    }

    var practiceLocalizationStatusText: String? {
        switch practiceLocalizationState {
            case .idle:
                nil
            case let .blocked(reason), let .failed(reason):
                reason.message
            case .openingImmersive:
                "正在打开沉浸空间…"
            case .waitingForProviders:
                "正在启动追踪服务…"
            case let .locating(elapsedSeconds, totalSeconds):
                "正在定位钢琴…（\(elapsedSeconds)/\(totalSeconds)s）"
            case .ready:
                "定位成功，已开始引导。"
        }
    }

    var canRetryPracticeLocalization: Bool {
        if case .failed = practiceLocalizationState {
            return true
        }
        return false
    }

    var shouldSuggestCalibrationStep: Bool {
        let reason: PracticeLocalizationFailure
        switch practiceLocalizationState {
            case let .blocked(blockingReason), let .failed(blockingReason):
                reason = blockingReason
            default:
                return false
        }

        switch reason {
            case .missingStoredCalibration, .anchorMissing, .anchorNotTracked, .anchorsTooClose:
                return true
            default:
                return false
        }
    }

    var step3ARStatusText: String {
        let worldState = appState.arTrackingService.providerStateByName["world"] ?? .idle
        switch worldState {
            case .running:
                return "AR 定位：可用"
            case .unsupported:
                return "AR 定位：不可用（设备/环境不支持）"
            case let .failed(reason):
                return "AR 定位：失败（\(reason)）"
            default:
                return "AR 定位：初始化中"
        }
    }

    var step3HandAssistStatusText: String {
        let handState = appState.arTrackingService.providerStateByName["hand"] ?? .idle
        switch handState {
            case .running:
                return "手势辅助：可用（boost + fallback）"
            case .disabled:
                return "手势辅助：已关闭（Bluetooth MIDI 模式）"
            case .unauthorized:
                return "手势辅助：不可用（未授权）"
            case let .failed(reason):
                return "手势辅助：不可用（\(reason)）"
            default:
                return "手势辅助：初始化中"
        }
    }

    var step3AudioStatusText: String {
        switch practiceSessionViewModel.audioRecognitionStatus {
            case .idle:
                "音频识别：空闲"
            case .requestingPermission:
                "音频识别：请求麦克风权限"
            case .permissionDenied:
                "音频识别：权限被拒绝"
            case .running:
                "音频识别：运行中"
            case let .engineFailed(reason):
                "音频识别：引擎失败（\(reason)）"
            case .stopped:
                "音频识别：已停止"
        }
    }

    var practiceProgressText: String {
        guard practiceSetupState.importedSteps.isEmpty == false else { return "0 / 0" }
        let total = practiceSetupState.importedSteps.count
        switch practiceSessionViewModel.state {
            case .idle, .ready:
                return "0 / \(total)"
            case let .guiding(index):
                return "\(min(index + 1, total)) / \(total)"
            case .completed:
                return "\(total) / \(total)"
        }
    }

    func updatePracticeSession(_ practiceSessionViewModel: PracticeSessionViewModel) {
        self.practiceSessionViewModel = practiceSessionViewModel
    }

    func practiceEntryBlockingReason() -> PracticeLocalizationFailure? {
        if practiceSetupState.importedSteps.isEmpty {
            return .missingImportedSteps
        }

        if placementViewModel.isVirtualPianoEnabled == false, appState.storedCalibration == nil {
            return .missingStoredCalibration
        }

        return nil
    }

    func enterPracticeStep(
        replacePracticeSessionViewModel: () -> Void,
        openImmersiveSpace: PracticeImmersiveOpenHandler,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler
    ) async {
        replacePracticeSessionViewModel()
        await beginPracticeLocalization(
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func retryPracticeLocalization(
        replacePracticeSessionViewModel: () -> Void,
        openImmersiveSpace: PracticeImmersiveOpenHandler,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler
    ) async {
        replacePracticeSessionViewModel()
        await beginPracticeLocalization(
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace
        )
    }

    func enterVirtualPianoPlacement(openImmersiveSpace: PracticeImmersiveOpenHandler) async {
        guard placementViewModel.isVirtualPianoEnabled == false else { return }
        placementViewModel.setPracticeVirtualPianoEnabled(true)
        placementViewModel.isVirtualPianoPlaced = false

        practiceLocalizationViewModel.setPracticeLocalizationState(.openingImmersive)
        if let openError = await openImmersiveForStep(mode: .practice, openImmersiveSpace: openImmersiveSpace) {
            practiceLocalizationViewModel.setPracticeLocalizationState(.failed(reason: .immersiveOpenFailed(message: openError)))
            return
        }

        practiceLocalizationViewModel.setPracticeLocalizationState(.ready)
    }

    func resetPracticeLocalizationState() {
        practiceLocalizationViewModel.resetPracticeLocalizationState()
    }

    func practiceLocalizationTimeoutFailure(
        lastRecoverableResolution: AppState.PracticeCalibrationResolutionResult?
    ) -> PracticeLocalizationFailure {
        practiceLocalizationViewModel.practiceLocalizationTimeoutFailure(
            lastRecoverableResolution: lastRecoverableResolution
        )
    }

    func openImmersiveForStep(
        mode: AppState.ImmersiveMode,
        openImmersiveSpace: PracticeImmersiveOpenHandler
    ) async -> String? {
        appState.immersiveMode = mode

        switch appState.immersiveSpaceState {
            case .open:
                return nil

            case .inTransition:
                for _ in 0 ..< 40 {
                    await Task.yield()
                    if appState.immersiveSpaceState != .inTransition {
                        break
                    }
                }

                if appState.immersiveSpaceState == .closed {
                    return await openImmersiveForStep(mode: mode, openImmersiveSpace: openImmersiveSpace)
                }
                return nil

            case .closed:
                appState.immersiveSpaceState = .inTransition
                switch await openImmersiveSpace(appState.immersiveSpaceID) {
                    case .opened:
                        // ImmersiveView.onAppear is the single source of truth for `.open`.
                        return nil

                    case .userCancelled:
                        appState.immersiveSpaceState = .closed
                        return "已取消打开沉浸空间。"

                    case .error:
                        appState.immersiveSpaceState = .closed
                        return "打开沉浸空间失败，请重试。"

                    case .unknown:
                        appState.immersiveSpaceState = .closed
                        return "沉浸空间返回未知状态，请重试。"
                }
        }
    }

    func closeImmersiveForStep(dismissImmersiveSpace: PracticeImmersiveDismissHandler) async {
        guard appState.immersiveSpaceState != .closed else { return }
        if appState.immersiveSpaceState == .open {
            appState.immersiveSpaceState = .inTransition
        }
        await dismissImmersiveSpace()
        // ImmersiveView.onDisappear is the single source of truth for `.closed`.
    }

    func recoverImmersiveStateIfStuck() async {
        guard appState.immersiveSpaceState == .inTransition else { return }
        for _ in 0 ..< 40 {
            await Task.yield()
            if appState.immersiveSpaceState != .inTransition {
                return
            }
        }
        appState.immersiveSpaceState = .closed
    }

    private func beginPracticeLocalization(
        openImmersiveSpace: PracticeImmersiveOpenHandler,
        dismissImmersiveSpace: @escaping PracticeImmersiveDismissHandler
    ) async {
        await practiceLocalizationViewModel.beginPracticeLocalization(
            isVirtualPianoEnabled: placementViewModel.isVirtualPianoEnabled,
            blockingReason: practiceEntryBlockingReason(),
            openImmersiveSpace: openImmersiveSpace,
            dismissImmersiveSpace: dismissImmersiveSpace,
            openImmersiveForStep: { [weak self] open in
                guard let self else { return "已退出练习流程。" }
                return await self.openImmersiveForStep(mode: .practice, openImmersiveSpace: open)
            },
            closeImmersiveForStep: { [weak self] dismiss in
                guard let self else { return }
                await self.closeImmersiveForStep(dismissImmersiveSpace: dismiss)
            },
            recoverImmersiveStateIfStuck: { [weak self] in
                guard let self else { return }
                await self.recoverImmersiveStateIfStuck()
            }
        )
    }
}
