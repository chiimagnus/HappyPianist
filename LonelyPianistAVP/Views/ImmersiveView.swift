import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var handDebugOverlayController = HandDebugOverlayController()

    var body: some View {
        RealityView { content in
            calibrationOverlayController.update(
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
                a0TrackedAnchorPoint: viewModel.a0OverlayPoint,
                c8TrackedAnchorPoint: viewModel.c8OverlayPoint,
                content: content
            )
            handDebugOverlayController.update(
                fingerTipPositions: viewModel.arTrackingService.fingerTipPositions,
                content: content
            )
            overlayController.updateHighlights(
                currentStep: viewModel.practiceSessionViewModel.currentStep,
                keyRegions: viewModel.practiceSessionViewModel.keyRegions,
                feedbackState: viewModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        } update: { content in
            calibrationOverlayController.update(
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
                a0TrackedAnchorPoint: viewModel.a0OverlayPoint,
                c8TrackedAnchorPoint: viewModel.c8OverlayPoint,
                content: content
            )
            handDebugOverlayController.update(
                fingerTipPositions: viewModel.arTrackingService.fingerTipPositions,
                content: content
            )
            overlayController.updateHighlights(
                currentStep: viewModel.practiceSessionViewModel.currentStep,
                keyRegions: viewModel.practiceSessionViewModel.keyRegions,
                feedbackState: viewModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            viewModel.onImmersiveDisappear()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let appModel = AppModel()
    ImmersiveView(viewModel: ARGuideViewModel(appModel: appModel))
}
