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

    func saveCalibration() {
        appModel.saveCalibrationIfPossible()
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

    func onImmersiveAppear() {
        if hasStartedGuidingInCurrentImmersiveSession == false {
            practiceSessionViewModel.startGuidingIfReady()
            hasStartedGuidingInCurrentImmersiveSession = true
        }
        startHandTrackingIfNeeded()
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

    func stopARGuide(using dismissImmersiveSpace: DismissImmersiveSpaceAction) {
        Task { @MainActor in
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        }
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
}
