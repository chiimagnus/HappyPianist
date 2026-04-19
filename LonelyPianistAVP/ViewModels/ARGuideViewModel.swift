import Foundation
import Observation
import SwiftUI
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    private let appModel: AppModel
    private var handTrackingConsumerTask: Task<Void, Never>?
    private var hasStartedGuidingInCurrentImmersiveSession = false
    private var wasRightHandPinching = false

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var calibration: PianoCalibration? {
        appModel.calibration
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

    var handTrackingService: HandTrackingService {
        appModel.handTrackingService
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
            handleModeEntryWhileImmersiveIsOpen()
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

    func enterInactiveMode() {
        appModel.immersiveMode = .inactive
        hasStartedGuidingInCurrentImmersiveSession = false
        wasRightHandPinching = false
        stopHandTracking()
    }

    func onImmersiveAppear() {
        handleModeEntryWhileImmersiveIsOpen()
    }

    func onImmersiveDisappear() {
        hasStartedGuidingInCurrentImmersiveSession = false
        stopHandTracking()
    }

    func startHandTrackingIfNeeded() {
        guard handTrackingConsumerTask == nil else { return }
        handTrackingService.start()
        let updates = handTrackingService.fingerTipUpdatesStream()
        handTrackingConsumerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await fingerTips in updates {
                guard Task.isCancelled == false else { return }
                switch self.appModel.immersiveMode {
                case .calibration:
                    self.handleCalibrationHandUpdates()
                case .practice:
                    _ = self.practiceSessionViewModel.handleFingerTipPositions(fingerTips)
                case .inactive:
                    break
                }
            }
        }
    }

    private func handleModeEntryWhileImmersiveIsOpen() {
        switch appModel.immersiveMode {
        case .inactive:
            hasStartedGuidingInCurrentImmersiveSession = false
            wasRightHandPinching = false
            stopHandTracking()

        case .calibration:
            hasStartedGuidingInCurrentImmersiveSession = false
            wasRightHandPinching = false
            startHandTrackingIfNeeded()
            if calibrationStatusMessage == nil, case .unavailable(let reason) = handTrackingService.state {
                calibrationStatusMessage = "手部追踪不可用：\(reason)"
            }

        case .practice:
            if hasStartedGuidingInCurrentImmersiveSession == false {
                practiceSessionViewModel.startGuidingIfReady()
                hasStartedGuidingInCurrentImmersiveSession = true
            }
            startHandTrackingIfNeeded()
        }
    }

    private func handleCalibrationHandUpdates() {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        calibrationCaptureService.updateReticleFromHandTracking(
            handTrackingService.leftIndexFingerTipPosition,
            nowUptime: nowUptime
        )

        let isRightHandPinching: Bool = {
            guard
                let rightIndex = handTrackingService.rightIndexFingerTipPosition,
                let rightThumb = handTrackingService.rightThumbTipPosition
            else {
                return false
            }
            let pinchDistanceThresholdMeters: Float = 0.018
            return simd_length(rightIndex - rightThumb) < pinchDistanceThresholdMeters
        }()

        if isRightHandPinching, wasRightHandPinching == false {
            confirmPendingCalibrationAnchorIfReady()
        }
        wasRightHandPinching = isRightHandPinching
    }

    private func confirmPendingCalibrationAnchorIfReady() {
        guard let pendingAnchor = pendingCalibrationCaptureAnchor else { return }
        guard calibrationCaptureService.isReticleReadyToConfirm else {
            calibrationStatusMessage = "请先将左手食指放稳在 \(pendingAnchor == .a0 ? "A0" : "C8") 键上（等待准星变绿），再用右手捏合确认。"
            return
        }
        calibrationCaptureService.capture(pendingAnchor)
        calibrationStatusMessage = "已锁定 \(pendingAnchor == .a0 ? "A0" : "C8")"
        pendingCalibrationCaptureAnchor = nil
    }

    func stopHandTracking() {
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        handTrackingService.stop()
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
}
