import ARKit
import Foundation
import Observation
import os
import simd

extension ARGuideViewModel {
    var calibration: PianoCalibration? {
        appState.calibration
    }

    var storedCalibration: StoredWorldAnchorCalibration? {
        appState.storedCalibration
    }

    var calibrationPhase: CalibrationPhase {
        calibrationFlowViewModel.calibrationPhase
    }

    var a0OverlayPoint: SIMD3<Float>? {
        let anchorID = calibrationCaptureService.a0AnchorID ?? storedCalibration?.a0AnchorID
        return resolvedTrackedWorldAnchorPoint(anchorID: anchorID)
    }

    var c8OverlayPoint: SIMD3<Float>? {
        let anchorID = calibrationCaptureService.c8AnchorID ?? storedCalibration?.c8AnchorID
        return resolvedTrackedWorldAnchorPoint(anchorID: anchorID)
    }

    var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint? {
        get { appState.pendingCalibrationCaptureAnchor }
        set { appState.pendingCalibrationCaptureAnchor = newValue }
    }

    var calibrationStatusMessage: String? {
        get { appState.calibrationStatusMessage }
        set { appState.calibrationStatusMessage = newValue }
    }

    var calibrationCaptureService: CalibrationPointCaptureService {
        appState.calibrationCaptureService
    }

    var arTrackingService: ARTrackingServiceProtocol {
        appState.arTrackingService
    }

    var hasImportedSteps: Bool {
        flowState.importedSteps.isEmpty == false
    }

    var immersiveMode: AppState.ImmersiveMode {
        appState.immersiveMode
    }

    var immersiveSpaceState: AppState.ImmersiveSpaceState {
        appState.immersiveSpaceState
    }

    func saveCalibration() {
        _ = appState.saveCalibrationIfPossible()
    }

    func beginCalibrationRecapture() {
        appState.beginCalibrationRecapture()
    }

    func beginCalibrationGuidedFlow() {
        calibrationFlowViewModel.beginCalibrationGuidedFlow()
    }

    func presentCalibrationError(message: String) {
        calibrationFlowViewModel.presentCalibrationError(message: message)
    }

    func endCalibrationGuidedFlow() {
        calibrationFlowViewModel.endCalibrationGuidedFlow()
    }

    @discardableResult
    func showCalibrationCompletedIfStoredCalibrationExists() -> Bool {
        calibrationFlowViewModel.showCalibrationCompletedIfStoredCalibrationExists()
    }

    func skipStep() {
        practiceSessionViewModel.skip()
    }

    func playCurrentPracticeStepSound() {
        practiceSessionViewModel.playCurrentStepSound()
    }

    func replayCurrentPracticeUnit() {
        practiceSessionViewModel.replayCurrentUnit()
    }

    func setPracticeAutoplayEnabled(_ isEnabled: Bool) {
        practiceSessionViewModel.setAutoplayEnabled(isEnabled)
    }

    func setPracticeVirtualPianoEnabled(_ isEnabled: Bool) {
        isVirtualPianoEnabled = isEnabled
        if isEnabled {
            practiceSessionViewModel.stopVirtualPianoInput()
            practiceSessionViewModel.clearCalibration()
            practiceLocalizationViewModel.shutdown()
            gazePlaneDiskConfirmation.reset()
            latestGazePlaneHit = nil
            startVirtualPianoGuidanceIfNeeded()
            #if DEBUG && targetEnvironment(simulator)
                practiceLocalizationViewModel.setPracticeLocalizationState(.ready)
                if appState.cachedVirtualPianoWorldAnchorID == nil {
                    applyVirtualPianoGeometryAtDefaultPositionForSimulator()
                }
            #else
                if appState.cachedVirtualPianoWorldAnchorID == nil {
                    practiceLocalizationViewModel.setPracticeLocalizationState(.idle)
                }
            #endif
        } else {
            practiceSessionViewModel.stopVirtualPianoInput()
            practiceSessionViewModel.clearCalibration()
            practiceLocalizationViewModel.setPracticeLocalizationState(.idle)
            gazePlaneDiskConfirmation.reset()
            latestGazePlaneHit = nil
            stopVirtualPianoGuidance()
        }
    }

    func setPracticeVirtualPerformerEnabled(_ isEnabled: Bool) {
        isVirtualPerformerEnabled = isEnabled
        aiPerformanceCoordinator.updatePracticeSession(practiceSessionViewModel)
        aiPerformanceCoordinator.setEnabled(isEnabled)
    }

    var backendStatusText: String? {
        switch backendDiscoveryService.state {
            case .idle:
                "Backend: idle"
            case .discovering:
                "Backend: discovering"
            case let .resolved(host, port):
                "Backend: resolved \(host):\(port)"
            case let .failed(message):
                "Backend: unavailable (\(message))"
            case .denied:
                "Backend: denied (Local Network)"
        }
    }

    var gazePlaneDiskStatusText: String? {
        guard isVirtualPianoEnabled else { return nil }
        if practiceSessionViewModel.keyboardGeometry != nil {
            return nil
        }

        let planeState = arTrackingService.providerStateByName["plane"] ?? .idle
        switch planeState {
            case .unsupported:
                return "虚拟钢琴不可用：此设备/环境不支持平面检测。"
            case .unauthorized:
                return "虚拟钢琴不可用：请在系统设置中允许本 App 使用“周围环境/世界感知”（worldSensing）。"
            case let .failed(reason):
                return "虚拟钢琴不可用：平面检测启动失败（\(reason)）。"
            default:
                break
        }

        let handState = arTrackingService.providerStateByName["hand"] ?? .idle
        switch handState {
            case .unsupported:
                return "虚拟钢琴不可用：此设备不支持手部追踪。"
            case .unauthorized:
                return "虚拟钢琴：已检测到平面，但需要 Hand Tracking 才能确认放好双手。"
            case let .failed(reason):
                return "虚拟钢琴不可用：手部追踪启动失败（\(reason)）。"
            default:
                break
        }

        return gazePlaneDiskConfirmation.statusText
    }

    var isGazePlaneDiskVisible: Bool {
        isVirtualPianoEnabled &&
            practiceSessionViewModel.keyboardGeometry == nil &&
            gazePlaneDiskConfirmation.isDiskVisible
    }

    var gazePlaneDiskWorldTransform: simd_float4x4? {
        guard isGazePlaneDiskVisible else { return nil }
        return gazePlaneDiskConfirmation.diskWorldTransform
    }

    var gazePlaneDiskOverlayText: String? {
        guard isGazePlaneDiskVisible else { return nil }
        return gazePlaneDiskConfirmation.statusText
    }

    var gazePlaneDiskCameraWorldPosition: SIMD3<Float>? {
        guard isGazePlaneDiskVisible else { return nil }
        return latestGazeRayOriginWorld
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

    func retryVirtualPianoPlacement() {
        guard isVirtualPianoEnabled else { return }

        practiceSessionViewModel.stopVirtualPianoInput()
        practiceSessionViewModel.clearCalibration()
        if let anchorID = appState.cachedVirtualPianoWorldAnchorID {
            appState.cachedVirtualPianoWorldAnchorID = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await arTrackingService.worldTrackingProvider.removeAnchor(forID: anchorID)
            }
        }

        gazePlaneDiskConfirmation.reset()
        latestGazePlaneHit = nil

        #if DEBUG && targetEnvironment(simulator)
            applyVirtualPianoGeometryAtDefaultPositionForSimulator()
        #endif
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
        let worldState = arTrackingService.providerStateByName["world"] ?? .idle
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
        let handState = arTrackingService.providerStateByName["hand"] ?? .idle
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

    func practiceEntryBlockingReason() -> PracticeLocalizationFailure? {
        if hasImportedSteps == false {
            return .missingImportedSteps
        }

        if isVirtualPianoEnabled == false, storedCalibration == nil {
            return .missingStoredCalibration
        }

        return nil
    }


}
