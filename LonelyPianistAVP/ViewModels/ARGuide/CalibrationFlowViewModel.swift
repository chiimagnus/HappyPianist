import ARKit
import Foundation
import Observation
import simd

@MainActor
@Observable
final class CalibrationFlowViewModel {
    enum CalibrationPhase: Equatable {
        case capturingA0
        case transitionA0
        case capturingC8
        case transitionC8
        case completed
        case error(message: String)
    }

    private let appState: AppState
    private let arTrackingService: ARTrackingServiceProtocol

    private var calibrationAnchorCaptureTask: Task<Void, Never>?
    private var calibrationFlowBootstrapTask: Task<Void, Never>?
    private var calibrationGuidedFlowTask: Task<Void, Never>?
    private var calibrationSupportPollTask: Task<Void, Never>?

    private var wasRightHandPinching = false
    private var wasLeftHandPinching = false

    private(set) var calibrationPhase: CalibrationPhase = .capturingA0

    init(appState: AppState) {
        self.appState = appState
        arTrackingService = appState.arTrackingService
    }

    private var storedCalibration: StoredWorldAnchorCalibration? {
        appState.storedCalibration
    }

    private var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint? {
        get { appState.pendingCalibrationCaptureAnchor }
        set { appState.pendingCalibrationCaptureAnchor = newValue }
    }

    private var calibrationStatusMessage: String? {
        get { appState.calibrationStatusMessage }
        set { appState.calibrationStatusMessage = newValue }
    }

    private var calibrationCaptureService: CalibrationPointCaptureService {
        appState.calibrationCaptureService
    }

    func shutdown() {
        cancelCalibrationGuidedFlowTasks()
        calibrationAnchorCaptureTask?.cancel()
        calibrationAnchorCaptureTask = nil
        wasRightHandPinching = false
        wasLeftHandPinching = false
    }

    func onImmersiveAppear() {
        guard appState.immersiveMode == .calibration else { return }
        wasRightHandPinching = false
        wasLeftHandPinching = false
        startCalibrationSupportPollingIfNeeded()
        updateCalibrationTrackingStatusIfNeeded()
    }

    func stopHandTracking() {
        calibrationAnchorCaptureTask?.cancel()
        calibrationAnchorCaptureTask = nil
        calibrationSupportPollTask?.cancel()
        calibrationSupportPollTask = nil
        wasRightHandPinching = false
        wasLeftHandPinching = false
    }

    func beginCalibrationGuidedFlow() {
        cancelCalibrationGuidedFlowTasks()
        calibrationPhase = .capturingA0
        calibrationFlowBootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            appState.beginCalibrationRecapture()

            for _ in 0 ..< 40 {
                guard Task.isCancelled == false else { return }
                if calibrationCaptureService.a0AnchorID == nil,
                   calibrationCaptureService.c8AnchorID == nil
                {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            calibrationStatusMessage = nil
            pendingCalibrationCaptureAnchor = .a0
            calibrationPhase = .capturingA0
            calibrationFlowBootstrapTask = nil
        }
    }

    func presentCalibrationError(message: String) {
        cancelCalibrationGuidedFlowTasks()
        calibrationStatusMessage = message
        pendingCalibrationCaptureAnchor = nil
        calibrationPhase = .error(message: message)
    }

    func endCalibrationGuidedFlow() {
        cancelCalibrationGuidedFlowTasks()
    }

    @discardableResult
    func showCalibrationCompletedIfStoredCalibrationExists() -> Bool {
        guard storedCalibration != nil else { return false }
        endCalibrationGuidedFlow()
        calibrationStatusMessage = nil
        pendingCalibrationCaptureAnchor = nil
        calibrationPhase = .completed
        return true
    }

    func handleHandUpdates() {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let reticleSourcePoint: SIMD3<Float>? = switch pendingCalibrationCaptureAnchor {
            case .c8:
                arTrackingService.rightIndexFingerTipPosition
            case .a0, .none:
                arTrackingService.leftIndexFingerTipPosition
        }
        calibrationCaptureService.updateReticleFromHandTracking(
            reticleSourcePoint,
            nowUptime: nowUptime
        )
        updateCalibrationTrackingStatusIfNeeded()

        let pinchDistanceThresholdMeters: Float = 0.018

        let isLeftHandPinching: Bool = {
            guard
                let leftIndex = arTrackingService.leftIndexFingerTipPosition,
                let leftThumb = arTrackingService.leftThumbTipPosition
            else {
                return false
            }
            return simd_length(leftIndex - leftThumb) < pinchDistanceThresholdMeters
        }()

        let isRightHandPinching: Bool = {
            guard
                let rightIndex = arTrackingService.rightIndexFingerTipPosition,
                let rightThumb = arTrackingService.rightThumbTipPosition
            else {
                return false
            }
            return simd_length(rightIndex - rightThumb) < pinchDistanceThresholdMeters
        }()

        let shouldConfirmOnPinch: Bool = switch pendingCalibrationCaptureAnchor {
            case .a0, .none:
                isRightHandPinching && wasRightHandPinching == false
            case .c8:
                isLeftHandPinching && wasLeftHandPinching == false
        }

        if shouldConfirmOnPinch {
            calibrationAnchorCaptureTask?.cancel()
            calibrationAnchorCaptureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await confirmPendingCalibrationAnchorIfReady()
                calibrationAnchorCaptureTask = nil
            }
        }
        wasRightHandPinching = isRightHandPinching
        wasLeftHandPinching = isLeftHandPinching
    }

    private func updateCalibrationTrackingStatusIfNeeded() {
        guard appState.immersiveMode == .calibration else { return }
        guard calibrationPhase != .completed else { return }

        let handState = arTrackingService.providerStateByName["hand"] ?? .idle
        let worldState = arTrackingService.providerStateByName["world"] ?? .idle
        let failureMessage: String? = switch (handState, worldState) {
            case (.unsupported, _):
                "手部追踪不可用：此设备不支持手部追踪。"
            case (.unauthorized, _):
                "手部追踪未授权：请在系统设置中允许本 App 使用 Hand Tracking。"
            case let (.failed(reason), _):
                "手部追踪启动失败：\(reason)"
            case (_, .unsupported):
                "世界追踪不可用：此环境不支持 World Tracking。"
            case (_, .unauthorized):
                "世界追踪不可用：WorldTrackingProvider 未能启动（请稍后重试）。"
            case let (_, .failed(reason)):
                "世界追踪启动失败：\(reason)"
            default:
                nil
        }

        guard let failureMessage else { return }
        presentCalibrationError(message: failureMessage)
    }

    private func confirmPendingCalibrationAnchorIfReady() async {
        guard let pendingAnchor = pendingCalibrationCaptureAnchor else { return }
        guard calibrationCaptureService.isReticleReadyToConfirm else {
            let fingerText = pendingAnchor == .a0 ? "左手食指" : "右手食指"
            let keyText = pendingAnchor == .a0 ? "A0" : "C8"
            let pinchHandText = pendingAnchor == .a0 ? "右手" : "左手"
            calibrationStatusMessage = "请先将\(fingerText)放稳在 \(keyText) 键上（等待准星变绿），再用\(pinchHandText)捏合确认。"
            return
        }

        let oldAnchorID = calibrationCaptureService.anchorID(for: pendingAnchor)
        let reticlePoint = calibrationCaptureService.reticlePoint

        var anchorTransform = matrix_identity_float4x4
        anchorTransform.columns.3 = SIMD4<Float>(reticlePoint.x, reticlePoint.y, reticlePoint.z, 1)
        let worldAnchor = WorldAnchor(originFromAnchorTransform: anchorTransform)

        do {
            try await arTrackingService.worldTrackingProvider.addAnchor(worldAnchor)
            calibrationCaptureService.setAnchorID(worldAnchor.id, for: pendingAnchor)
            calibrationStatusMessage = "已锁定 \(pendingAnchor == .a0 ? "A0" : "C8")"
            pendingCalibrationCaptureAnchor = nil
            onCalibrationAnchorConfirmed(pendingAnchor)

            if let oldAnchorID,
               oldAnchorID != worldAnchor.id,
               let oldAnchor = arTrackingService.worldAnchorsByID[oldAnchorID]
            {
                try? await arTrackingService.worldTrackingProvider.removeAnchor(oldAnchor)
            }
        } catch {
            calibrationStatusMessage = "锁定失败：\(error.localizedDescription)"
            presentCalibrationError(message: calibrationStatusMessage ?? "锁定失败")
        }
    }

    private func onCalibrationAnchorConfirmed(_ anchor: CalibrationAnchorPoint) {
        guard calibrationPhase != .completed else { return }
        if case .error = calibrationPhase { return }

        calibrationGuidedFlowTask?.cancel()
        calibrationGuidedFlowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            switch anchor {
                case .a0:
                    calibrationPhase = .transitionA0
                    calibrationStatusMessage = nil
                    try? await Task.sleep(for: .seconds(1.25))
                    guard Task.isCancelled == false else { return }
                    pendingCalibrationCaptureAnchor = .c8
                    calibrationPhase = .capturingC8

                case .c8:
                    calibrationPhase = .transitionC8
                    let capturedA0 = calibrationCaptureService.a0AnchorID
                    let capturedC8 = calibrationCaptureService.c8AnchorID
                    calibrationStatusMessage = nil
                    try? await Task.sleep(for: .seconds(0.3))
                    guard Task.isCancelled == false else { return }

                    let didSave = appState.saveCalibrationIfPossible()
                    if didSave,
                       let storedCalibration,
                       storedCalibration.a0AnchorID == capturedA0,
                       storedCalibration.c8AnchorID == capturedC8
                    {
                        calibrationStatusMessage = nil
                        calibrationPhase = .completed
                    } else {
                        let message = calibrationStatusMessage ?? "保存校准失败，请重试。"
                        presentCalibrationError(message: message)
                    }
            }

            calibrationGuidedFlowTask = nil
        }
    }

    private func startCalibrationSupportPollingIfNeeded() {
        guard appState.immersiveMode == .calibration else { return }
        guard calibrationSupportPollTask == nil else { return }

        calibrationSupportPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0 ..< 40 {
                guard Task.isCancelled == false else { return }
                updateCalibrationTrackingStatusIfNeeded()
                if case .error = calibrationPhase { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            calibrationSupportPollTask = nil
        }
    }

    private func cancelCalibrationGuidedFlowTasks() {
        calibrationFlowBootstrapTask?.cancel()
        calibrationFlowBootstrapTask = nil
        calibrationGuidedFlowTask?.cancel()
        calibrationGuidedFlowTask = nil
        calibrationSupportPollTask?.cancel()
        calibrationSupportPollTask = nil
    }

    #if DEBUG
        func setCalibrationPhaseForPreview(_ phase: CalibrationPhase) {
            calibrationPhase = phase
        }
    #endif
}

