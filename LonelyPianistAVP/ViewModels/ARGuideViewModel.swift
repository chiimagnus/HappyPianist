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

    func saveCalibration() {
        appModel.saveCalibrationIfPossible()
    }

    func beginCalibrationRecapture() {
        appModel.beginCalibrationRecapture()
    }

    func enterManualAdjustMode() {
        calibrationCaptureService.updateReticleEstimate(nil)
    }

    func adjust(anchor: CalibrationAnchorPoint, x: Float) {
        calibrationCaptureService.adjust(anchor: anchor, delta: SIMD3<Float>(x, 0, 0))
    }

    func handleSpatialTap(worldPoint: SIMD3<Float>) {
        calibrationCaptureService.updateReticleEstimate(worldPoint)
        if let pendingAnchor = pendingCalibrationCaptureAnchor {
            calibrationCaptureService.capture(pendingAnchor)
            calibrationStatusMessage = "已捕获 \(pendingAnchor == .a0 ? "A0" : "C8")"
            pendingCalibrationCaptureAnchor = nil
        }
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
        case .open, .inTransition:
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
        guard appModel.immersiveSpaceState == .open else { return }
        appModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
        // Don't set immersiveSpaceState to .closed here.
        // ImmersiveView.onDisappear is the single source of truth.
    }

    func onImmersiveAppear() {
        switch appModel.immersiveMode {
        case .calibration:
            hasStartedGuidingInCurrentImmersiveSession = false
            stopHandTracking()

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
        handTrackingService.start()
        let updates = handTrackingService.fingerTipUpdatesStream()
        handTrackingConsumerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await fingerTips in updates {
                guard Task.isCancelled == false else { return }
                _ = self.practiceSessionViewModel.handleFingerTipPositions(fingerTips)
            }
        }
    }

    func stopHandTracking() {
        handTrackingConsumerTask?.cancel()
        handTrackingConsumerTask = nil
        handTrackingService.stop()
    }

    var handTrackingStatusText: String {
        switch handTrackingService.state {
        case .idle:
            return "手部：空闲"
        case .running:
            return "手部：运行中（\(handTrackingService.fingerTipPositions.count) 个点）"
        case .unavailable(let reason):
            return "手部：不可用（\(reason)）"
        }
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
