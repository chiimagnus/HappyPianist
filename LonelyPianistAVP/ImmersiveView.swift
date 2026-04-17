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

    var body: some View {
        RealityView { content in
            appModel.practiceSessionViewModel.startGuidingIfReady()
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
            overlayController.updateHighlights(
                currentStep: appModel.practiceSessionViewModel.currentStep,
                keyRegions: appModel.practiceSessionViewModel.keyRegions,
                feedbackState: appModel.practiceSessionViewModel.feedbackState,
                content: content
            )
        }
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
