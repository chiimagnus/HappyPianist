import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Bindable var viewModel: ARGuideViewModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var handDebugOverlayController = HandDebugOverlayController()

    var body: some View {
        RealityView { content in
            viewModel.practiceSessionViewModel.startGuidingIfReady()
            calibrationOverlayController.update(
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                a0Point: viewModel.calibrationCaptureService.a0Point,
                c8Point: viewModel.calibrationCaptureService.c8Point,
                content: content
            )
            handDebugOverlayController.update(
                fingerTipPositions: viewModel.handTrackingService.fingerTipPositions,
                content: content
            )
            overlayController.updateHighlights(
                currentStep: viewModel.practiceSessionViewModel.currentStep,
                keyRegions: viewModel.practiceSessionViewModel.keyRegions,
                feedbackState: viewModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        } update: { content in
            _ = viewModel.practiceSessionViewModel.handleFingerTipPositions(
                viewModel.handTrackingService.fingerTipPositions
            )
            calibrationOverlayController.update(
                reticlePoint: viewModel.calibrationCaptureService.reticlePoint,
                a0Point: viewModel.calibrationCaptureService.a0Point,
                c8Point: viewModel.calibrationCaptureService.c8Point,
                content: content
            )
            handDebugOverlayController.update(
                fingerTipPositions: viewModel.handTrackingService.fingerTipPositions,
                content: content
            )
            overlayController.updateHighlights(
                currentStep: viewModel.practiceSessionViewModel.currentStep,
                keyRegions: viewModel.practiceSessionViewModel.keyRegions,
                feedbackState: viewModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        }
        .gesture(SpatialTapGesture(coordinateSpace3D: .worldReference).onEnded { value in
            let point3D = value.location3D
            let point = SIMD3<Float>(Float(point3D.x), Float(point3D.y), Float(point3D.z))
                viewModel.calibrationCaptureService.updateReticleEstimate(point)
                if let pendingAnchor = viewModel.pendingCalibrationCaptureAnchor {
                    viewModel.calibrationCaptureService.capture(pendingAnchor)
                    viewModel.calibrationStatusMessage = "已捕获 \(pendingAnchor == .a0 ? "A0" : "C8")"
                    viewModel.pendingCalibrationCaptureAnchor = nil
                }
            })
        .onAppear {
            viewModel.handTrackingService.start()
        }
        .onDisappear {
            viewModel.handTrackingService.stop()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let appModel = AppModel()
    ImmersiveView(viewModel: ARGuideViewModel(appModel: appModel))
}
