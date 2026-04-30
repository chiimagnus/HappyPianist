import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var keyboardAxesDebugOverlayController = KeyboardAxesDebugOverlayController()
    @State private var virtualPianoOverlayController = VirtualPianoOverlayController()
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false

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
                feedbackState: viewModel.practiceSessionViewModel.feedbackState,
                isAutoplayEnabled: viewModel.practiceSessionViewModel.autoplayState == .playing,
                content: content
            )
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoPlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            viewModel.syncVirtualPianoTransformFromOverlay(
                virtualPianoOverlayController.currentKeyboardWorldFromKeyboard()
            )
        } update: { content in
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
                feedbackState: viewModel.practiceSessionViewModel.feedbackState,
                isAutoplayEnabled: viewModel.practiceSessionViewModel.autoplayState == .playing,
                content: content
            )
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoPlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: content
            )
            viewModel.syncVirtualPianoTransformFromOverlay(
                virtualPianoOverlayController.currentKeyboardWorldFromKeyboard()
            )
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            viewModel.onImmersiveDisappear()
        }
        .onChange(of: viewModel.virtualPianoPlacement.state) {
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoPlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: nil
            )
        }
        .onChange(of: viewModel.practiceSessionViewModel.keyboardGeometry) {
            virtualPianoOverlayController.update(
                placementState: viewModel.virtualPianoPlacement.state,
                keyboardGeometry: viewModel.practiceSessionViewModel.keyboardGeometry,
                content: nil
            )
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let appState = AppState()
    ImmersiveView(viewModel: ARGuideViewModel(appState: appState))
}
