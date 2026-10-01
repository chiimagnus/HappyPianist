import Foundation
import Observation
import Practice

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
        case .paused:
            return "AR 定位：暂时暂停"
        case .stopped:
            return "AR 定位：已停止"
        case .disabled:
            return "AR 定位：已关闭"
        case .unsupported:
            return "AR 定位：不可用（设备/环境不支持）"
        case .unauthorized:
            return "AR 定位：不可用（未授权）"
        case let .failed(reason):
            return "AR 定位：失败（\(reason)）"
        case .idle:
            return "AR 定位：初始化中"
        }
    }

    var step3HandAssistStatusText: String {
        let handState = appState.arTrackingService.providerStateByName["hand"] ?? .idle
        switch handState {
        case .running:
            return "手势辅助：可用（boost + fallback）"
        case .paused:
            return "手势辅助：暂时暂停"
        case .stopped:
            return "手势辅助：已停止"
        case .disabled:
            return "手势辅助：已关闭（Bluetooth MIDI 模式）"
        case .unsupported:
            return "手势辅助：不可用（设备不支持）"
        case .unauthorized:
            return "手势辅助：不可用（未授权）"
        case let .failed(reason):
            return "手势辅助：不可用（\(reason)）"
        case .idle:
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

    func preparePracticeStep() {
        if placementViewModel.isVirtualPianoEnabled {
            placementViewModel.showVirtualPianoForPractice()
        }
    }

    func beginPracticeLocalization() {
        practiceLocalizationViewModel.beginPracticeLocalization(
            isVirtualPianoEnabled: placementViewModel.isVirtualPianoEnabled,
            blockingReason: practiceEntryBlockingReason()
        )
    }

    func prepareVirtualPianoPlacement() {
        if placementViewModel.isVirtualPianoEnabled == false {
            placementViewModel.isVirtualPianoPlaced = false
            placementViewModel.setPracticeVirtualPianoEnabled(true)
        } else {
            #if DEBUG && targetEnvironment(simulator)
                if placementViewModel.practiceSessionViewModel.keyboardGeometry == nil {
                    placementViewModel.applyVirtualPianoGeometryAtDefaultPositionForSimulator()
                }
            #endif
        }

        placementViewModel.showVirtualPianoForPlacement()

    }

    func markVirtualPianoPlacementReady() {
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

}
