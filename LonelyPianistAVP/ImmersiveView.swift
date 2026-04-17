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
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var overlayController = PianoGuideOverlayController()
    @State private var calibrationOverlayController = CalibrationOverlayController()
    @State private var handDebugOverlayController = HandDebugOverlayController()

    var body: some View {
        ZStack {
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
                    appModel.calibrationStatusMessage = "Captured \(pendingAnchor == .a0 ? "A0" : "C8")"
                    appModel.pendingCalibrationCaptureAnchor = nil
                }
            })

            guideHUDPanel
        }
        .onAppear {
            appModel.handTrackingService.start()
        }
        .onDisappear {
            appModel.handTrackingService.stop()
        }
    }

    private var guideHUDPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("AR Guide")
                    .font(.headline)
                Spacer()
                Button("Exit") {
                    Task { @MainActor in
                        await dismissImmersiveSpace()
                    }
                }
            }

            Text(handTrackingStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(practiceStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.importedSteps.isEmpty {
                Text("No score loaded. Import MusicXML in the window to start guiding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if appModel.calibration == nil {
                calibrationControls
            } else {
                practiceControls
            }

            if let message = appModel.calibrationStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .glassBackgroundEffect()
    }

    private var calibrationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calibration")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(appModel.pendingCalibrationCaptureAnchor == nil ? "Tap in space to preview the reticle." : "Tap in space to capture the selected anchor.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Set A0") { appModel.pendingCalibrationCaptureAnchor = .a0 }
                Button("Set C8") { appModel.pendingCalibrationCaptureAnchor = .c8 }
                Button("Save") { appModel.saveCalibrationIfPossible() }
            }

            Button("Manual Fallback") {
                appModel.calibrationCaptureService.updateReticleEstimate(nil)
            }

            if appModel.calibrationCaptureService.mode == .manualFallback {
                HStack(spacing: 8) {
                    Button("A0 ◀︎") {
                        appModel.calibrationCaptureService.adjust(anchor: .a0, delta: SIMD3<Float>(-0.01, 0, 0))
                    }
                    Button("A0 ▶︎") {
                        appModel.calibrationCaptureService.adjust(anchor: .a0, delta: SIMD3<Float>(0.01, 0, 0))
                    }
                    Button("C8 ◀︎") {
                        appModel.calibrationCaptureService.adjust(anchor: .c8, delta: SIMD3<Float>(-0.01, 0, 0))
                    }
                    Button("C8 ▶︎") {
                        appModel.calibrationCaptureService.adjust(anchor: .c8, delta: SIMD3<Float>(0.01, 0, 0))
                    }
                }
            }
        }
    }

    private var practiceControls: some View {
        HStack(spacing: 12) {
            Button("Skip") { appModel.practiceSessionViewModel.skip() }
            Button("Mark Correct") { appModel.practiceSessionViewModel.markCorrect() }
        }
    }

    private var handTrackingStatusText: String {
        switch appModel.handTrackingService.state {
        case .idle:
            return "Hands: idle"
        case .running:
            return "Hands: running (\(appModel.handTrackingService.fingerTipPositions.count) tips)"
        case .unavailable(let reason):
            return "Hands: unavailable (\(reason))"
        }
    }

    private var practiceStatusText: String {
        switch appModel.practiceSessionViewModel.state {
        case .idle:
            return "Practice: idle"
        case .ready:
            return "Practice: ready"
        case .guiding(let index):
            return "Practice: guiding (step \(index + 1))"
        case .completed:
            return "Practice: completed"
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
