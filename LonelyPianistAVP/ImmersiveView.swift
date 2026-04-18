//
//  ImmersiveView.swift
//  LonelyPianistAVP
//
//  Created by chii_magnus on 2026/4/6.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var handDebugOverlayController = HandDebugOverlayController()

    var body: some View {
        RealityView { content in
            appModel.practiceSessionViewModel.startGuidingIfReady()
            calibrationOverlayController.update(
                reticlePoint: appModel.calibrationCaptureService.reticlePoint,
                a0Point: appModel.calibrationCaptureService.a0Point,
                c8Point: appModel.calibrationCaptureService.c8Point,
                content: content
            )
            handDebugOverlayController.update(
                fingerTipPositions: appModel.handTrackingService.fingerTipPositions,
                content: content
            )
            overlayController.updateHighlights(
                currentStep: appModel.practiceSessionViewModel.currentStep,
                keyRegions: appModel.practiceSessionViewModel.keyRegions,
                feedbackState: appModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        } update: { content in
            _ = appModel.practiceSessionViewModel.handleFingerTipPositions(
                appModel.handTrackingService.fingerTipPositions
            )
            calibrationOverlayController.update(
                reticlePoint: appModel.calibrationCaptureService.reticlePoint,
                a0Point: appModel.calibrationCaptureService.a0Point,
                c8Point: appModel.calibrationCaptureService.c8Point,
                content: content
            )
            handDebugOverlayController.update(
                fingerTipPositions: appModel.handTrackingService.fingerTipPositions,
                content: content
            )
            overlayController.updateHighlights(
                currentStep: appModel.practiceSessionViewModel.currentStep,
                keyRegions: appModel.practiceSessionViewModel.keyRegions,
                feedbackState: appModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        }
        .gesture(SpatialTapGesture(coordinateSpace3D: .worldReference).onEnded { value in
            let point3D = value.location3D
            let point = SIMD3<Float>(Float(point3D.x), Float(point3D.y), Float(point3D.z))
                appModel.calibrationCaptureService.updateReticleEstimate(point)
                if let pendingAnchor = appModel.pendingCalibrationCaptureAnchor {
                    appModel.calibrationCaptureService.capture(pendingAnchor)
                    appModel.calibrationStatusMessage = "已捕获 \(pendingAnchor == .a0 ? "A0" : "C8")"
                    appModel.pendingCalibrationCaptureAnchor = nil
                }
            })
        .onAppear {
            appModel.handTrackingService.start()
        }
        .onDisappear {
            appModel.handTrackingService.stop()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
