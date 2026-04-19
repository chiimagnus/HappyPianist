import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var handDebugOverlayController = HandDebugOverlayController()

    var body: some View {
        RealityView { content in
            updateContent(content)
        } update: { content in
            updateContent(content)
        }
        .onAppear {
            viewModel.onImmersiveAppear()
        }
        .onDisappear {
            viewModel.onImmersiveDisappear()
        }
    }

    private func updateContent(_ content: RealityViewContent) {
        let immersiveMode = viewModel.immersiveMode

        calibrationOverlayController.update(
            isVisible: immersiveMode == .calibration,
            reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
            isReticleReadyToConfirm: viewModel.calibrationCaptureService.isReticleReadyToConfirm,
            a0Point: viewModel.calibrationCaptureService.a0Point,
            c8Point: viewModel.calibrationCaptureService.c8Point,
            content: content
        )

        handDebugOverlayController.update(
            fingerTipPositions: immersiveMode == .inactive ? [:] : viewModel.handTrackingService.fingerTipPositions,
            content: content
        )

        overlayController.updateHighlights(
            currentStep: immersiveMode == .practice ? viewModel.practiceSessionViewModel.currentStep : nil,
            keyRegions: viewModel.practiceSessionViewModel.keyRegions,
            feedbackState: viewModel.practiceSessionViewModel.feedbackState,
            content: content
        )
    }
}

#Preview(immersionStyle: .mixed) {
    let appModel = AppModel()
    ImmersiveView(viewModel: ARGuideViewModel(appModel: appModel))
}
