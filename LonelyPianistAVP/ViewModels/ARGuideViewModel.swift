import Foundation
import Observation
import SwiftUI
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    private let appModel: AppModel

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

    func skipStep() {
        practiceSessionViewModel.skip()
    }

    func markCorrect() {
        practiceSessionViewModel.markCorrect()
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
