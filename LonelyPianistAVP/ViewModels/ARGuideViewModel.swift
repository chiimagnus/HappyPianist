import ARKit
import Foundation
import Observation
import SwiftUI
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    private let appModel: AppModel
    private var handTrackingConsumerTask: Task<Void, Never>?
    private var calibrationAnchorCaptureTask: Task<Void, Never>?
    private var hasStartedGuidingInCurrentImmersiveSession = false
    private var wasRightHandPinching = false

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var calibration: PianoCalibration? {
        appModel.calibration
    }

    var storedCalibration: StoredWorldAnchorCalibration? {
        appModel.storedCalibration
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
        get { appModel.pendingCalibrationCaptureAnchor }
        set { appModel.pendingCalibrationCaptureAnchor = newValue }
    }

    var calibrationStatusMessage: String? {
        get { appModel.calibrationStatusMessage }
        set { appModel.calibrationStatusMessage = newValue }
    }

    var calibrationCaptureService: CalibrationPointCaptureService {
        appModel.calibrationCaptureService
    }

    var practiceSessionViewModel: PracticeSessionViewModel {
        appModel.practiceSessionViewModel
    }

    var arTrackingService: ARTrackingServiceProtocol {
        appModel.arTrackingService
    }

    var hasImportedSteps: Bool {
        appModel.importedSteps.isEmpty == false
    }

    var immersiveMode: AppModel.ImmersiveMode {
        appModel.immersiveMode
    }

    var immersiveSpaceState: AppModel.ImmersiveSpaceState {
        appModel.immersiveSpaceState
    }

    func saveCalibration() {
        appModel.saveCalibrationIfPossible()
    }

    func beginCalibrationRecapture() {
        appModel.beginCalibrationRecapture()
    }

    func skipStep() {
        practiceSessionViewModel.skip()
    }

    func markCorrect() {
        practiceSessionViewModel.markCorrect()
    }

    func openImmersiveForStep(
        mode: AppModel.ImmersiveMode,
        using openImmersiveSpace: OpenImmersiveSpaceAction
    ) async -> String? {
        appModel.immersiveMode = mode

        switch appModel.immersiveSpaceState {
        case .open:
            return nil

        case .inTransition:
            for _ in 0..<40 {
                await Task.yield()
                if appModel.immersiveSpaceState != .inTransition {
                    break
                }
            }

            if appModel.immersiveSpaceState == .closed {
                return await openImmersiveForStep(mode: mode, using: openImmersiveSpace)
            }
            return nil

        case .closed:
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                // Don't set immersiveSpaceState to .open here.
                // ImmersiveView.onAppear is the single source of truth.
                return nil

            case .userCancelled:
                appModel.immersiveSpaceState = .closed
                return "已取消打开沉浸空间。"

            case .error:
                appModel.immersiveSpaceState = .closed
                return "打开沉浸空间失败，请重试。"

            @unknown default:
                appModel.immersiveSpaceState = .closed
                return "沉浸空间返回未知状态，请重试。"
            }
        }
    }

    func closeImmersiveForStep(using dismissImmersiveSpace: DismissImmersiveSpaceAction) async {
        guard appModel.immersiveSpaceState != .closed else { return }
        if appModel.immersiveSpaceState == .open {
            appModel.immersiveSpaceState = .inTransition
        }
        await dismissImmersiveSpace()
        // Don't set immersiveSpaceState to .closed here.
        // ImmersiveView.onDisappear is the single source of truth.
    }

    func recoverImmersiveStateIfStuck() async {
        guard appModel.immersiveSpaceState == .inTransition else { return }
        for _ in 0..<40 {
            await Task.yield()
            if appModel.immersiveSpaceState != .inTransition {
                return
            }
        }
        appModel.immersiveSpaceState = .closed
    }

    func onImmersiveAppear() {
        switch appModel.immersiveMode {
        case .calibration:
            hasStartedGuidingInCurrentImmersiveSession = false
            wasRightHandPinching = false
            startHandTrackingIfNeeded()
            if calibrationStatusMessage == nil,
               arTrackingService.providerStateByName["hand"] == .unsupported {
                calibrationStatusMessage = "手部追踪不可用：此设备不支持手部追踪。"
            }

        case .practice:
            if hasStartedGuidingInCurrentImmersiveSession == false {
                practiceSessionViewModel.startGuidingIfReady()
                hasStartedGuidingInCurrentImmersiveSession = true
            }
            startHandTrackingIfNeeded()
        }
    }

    func onImmersiveDisappear() {
        hasStartedGuidingInCurrentImmersiveSession = false
        stopHandTracking()
    }

    func startHandTrackingIfNeeded() {
        guard handTrackingConsumerTask == nil else { return }
        arTrackingService.start()
        let updates = arTrackingService.fingerTipUpdatesStream()
        handTrackingConsumerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await fingerTips in updates {
                guard Task.isCancelled == false else { return }
                switch self.appModel.immersiveMode {
                case .calibration:
                    self.handleCalibrationHandUpdates()
                case .practice:
                    _ = self.practiceSessionViewModel.handleFingerTipPositions(fingerTips)
                }
            }
        }
    }

    private func handleCalibrationHandUpdates() {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        calibrationCaptureService.updateReticleFromHandTracking(
            arTrackingService.leftIndexFingerTipPosition,
            nowUptime: nowUptime
        )

        let isRightHandPinching: Bool = {
            guard
                let rightIndex = arTrackingService.rightIndexFingerTipPosition,
                let rightThumb = arTrackingService.rightThumbTipPosition
            else {
                return false
            }
            let pinchDistanceThresholdMeters: Float = 0.018
            return simd_length(rightIndex - rightThumb) < pinchDistanceThresholdMeters
        }()

        if isRightHandPinching, wasRightHandPinching == false {
            calibrationAnchorCaptureTask?.cancel()
            calibrationAnchorCaptureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.confirmPendingCalibrationAnchorIfReady()
                self.calibrationAnchorCaptureTask = nil
            }
        }
        wasRightHandPinching = isRightHandPinching
    }

    private func confirmPendingCalibrationAnchorIfReady() async {
        guard let pendingAnchor = pendingCalibrationCaptureAnchor else { return }
        guard calibrationCaptureService.isReticleReadyToConfirm else {
            calibrationStatusMessage = "请先将左手食指放稳在 \(pendingAnchor == .a0 ? "A0" : "C8") 键上（等待准星变绿），再用右手捏合确认。"
            return
        }

        let oldAnchorID = calibrationCaptureService.anchorID(for: pendingAnchor)
        let reticlePoint = calibrationCaptureService.reticlePoint

        var anchorTransform = matrix_identity_float4x4
        anchorTransform.columns.3 = SIMD4<Float>(reticlePoint.x, reticlePoint.y, reticlePoint.z, 1)
        let worldAnchor = WorldAnchor(originFromAnchorTransform: anchorTransform)

        do {
            try await arTrackingService.worldTrackingProvider.addAnchor(worldAnchor)
            calibrationCaptureService.capture(pendingAnchor)
            calibrationCaptureService.setAnchorID(worldAnchor.id, for: pendingAnchor)
            calibrationStatusMessage = "已锁定 \(pendingAnchor == .a0 ? "A0" : "C8")"
            pendingCalibrationCaptureAnchor = nil

            if let oldAnchorID,
               oldAnchorID != worldAnchor.id,
               let oldAnchor = arTrackingService.worldAnchorsByID[oldAnchorID] {
                try? await arTrackingService.worldTrackingProvider.removeAnchor(oldAnchor)
            }
        } catch {
            calibrationStatusMessage = "锁定失败：\(error.localizedDescription)"
        }
    }

    func stopHandTracking() {
        calibrationAnchorCaptureTask?.cancel()
        calibrationAnchorCaptureTask = nil
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        arTrackingService.stop()
    }

    var practiceStatusText: String {
        switch practiceSessionViewModel.state {
        case .idle:
            return "练习：空闲"
        case .ready:
            return "练习：就绪"
        case .guiding(let index):
            return "练习：引导中（第 \(index + 1) 步）"
        case .completed:
            return "练习：已完成"
        }
    }

    var practiceProgressText: String {
        guard appModel.importedSteps.isEmpty == false else { return "0 / 0" }
        let total = appModel.importedSteps.count
        let completedCount = min(practiceSessionViewModel.currentStepIndex, total)
        return "\(completedCount) / \(total)"
    }

    var canControlPractice: Bool {
        hasImportedSteps
    }

    private func resolvedTrackedWorldAnchorPoint(anchorID: UUID?) -> SIMD3<Float>? {
        guard let anchorID else { return nil }
        guard let anchor = arTrackingService.worldAnchorsByID[anchorID] else { return nil }
        guard anchor.isTracked else { return nil }

        let transform = anchor.originFromAnchorTransform
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
}
