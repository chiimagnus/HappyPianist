import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var keyboardAxesDebugOverlayController = KeyboardAxesDebugOverlayController()
    @State private var virtualPianoOverlayController = VirtualPianoOverlayController()
    @State private var gazePlaneDiskOverlayController = GazePlaneDiskOverlayController()
    @State private var virtualPerformerOverlayController = VirtualPerformerOverlayController()
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage("immersivePanoramaEnabled") private var immersivePanoramaEnabled = false
    @State private var panoramaController = PanoramaBackgroundController()

    private var desiredPanoramaBaseName: String? {
        guard let songName = viewModel.importedSongDisplayName, songName.isEmpty == false else {
            return nil
        }
        return songName
    }

    private var shouldShowCalibrationReticle: Bool {
        guard viewModel.immersiveMode == .calibration else { return false }
        switch viewModel.calibrationPhase {
            case .completed, .error:
                return false
            default:
                return true
        }
    }

    var body: some View {
        RealityView { content in
            panoramaController.update(
                isEnabled: immersivePanoramaEnabled,
                desiredBaseName: desiredPanoramaBaseName,
                content: content
            )

            calibrationOverlayController.update(
                showsReticle: shouldShowCalibrationReticle,
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
                a0TrackedAnchorPoint: viewModel.a0OverlayPoint,
                c8TrackedAnchorPoint: viewModel.c8OverlayPoint,
                content: content
            )
            keyboardAxesDebugOverlayController.update(
                isEnabled: debugKeyboardAxesOverlayEnabled,
                keyboardFrame: viewModel.practiceSessionViewModel.calibration?.keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: viewModel.practiceSessionViewModel.currentPianoHighlightGuide,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            gazePlaneDiskOverlayController.update(
                isVisible: viewModel.isGazePlaneDiskVisible,
                diskWorldTransform: viewModel.gazePlaneDiskWorldTransform,
                statusText: viewModel.gazePlaneDiskOverlayText,
                cameraWorldPosition: viewModel.gazePlaneDiskCameraWorldPosition,
                content: content
            )
            virtualPianoOverlayController.update(
                isEnabled: viewModel.isVirtualPianoEnabled,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            virtualPerformerOverlayController.update(
                isEnabled: viewModel.isVirtualPerformerEnabled,
                isPerforming: viewModel.isAIPerformanceActive,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                cameraWorldPosition: viewModel.latestDeviceWorldPosition,
                performanceSchedule: viewModel.latestAIPerformanceSchedule,
                content: content
            )
        } update: { content in
            panoramaController.update(
                isEnabled: immersivePanoramaEnabled,
                desiredBaseName: desiredPanoramaBaseName,
                content: content
            )

            calibrationOverlayController.update(
                showsReticle: shouldShowCalibrationReticle,
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
                a0TrackedAnchorPoint: viewModel.a0OverlayPoint,
                c8TrackedAnchorPoint: viewModel.c8OverlayPoint,
                content: content
            )
            keyboardAxesDebugOverlayController.update(
                isEnabled: debugKeyboardAxesOverlayEnabled,
                keyboardFrame: viewModel.practiceSessionViewModel.calibration?.keyboardFrame,
                content: content
            )
            overlayController.updateHighlights(
                highlightGuide: viewModel.practiceSessionViewModel.currentPianoHighlightGuide,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            gazePlaneDiskOverlayController.update(
                isVisible: viewModel.isGazePlaneDiskVisible,
                diskWorldTransform: viewModel.gazePlaneDiskWorldTransform,
                statusText: viewModel.gazePlaneDiskOverlayText,
                cameraWorldPosition: viewModel.gazePlaneDiskCameraWorldPosition,
                content: content
            )
            virtualPianoOverlayController.update(
                isEnabled: viewModel.isVirtualPianoEnabled,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            virtualPerformerOverlayController.update(
                isEnabled: viewModel.isVirtualPerformerEnabled,
                isPerforming: viewModel.isAIPerformanceActive,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                cameraWorldPosition: viewModel.latestDeviceWorldPosition,
                performanceSchedule: viewModel.latestAIPerformanceSchedule,
                content: content
            )
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            panoramaController.shutdown()
            viewModel.onImmersiveDisappear()
        }
    }
}

#Preview(immersionStyle: .progressive(0.0...1.0, initialAmount: 0.7, aspectRatio: nil)) {
    let appState = AppState()
    ImmersiveView(viewModel: ARGuideViewModel(appState: appState))
}
