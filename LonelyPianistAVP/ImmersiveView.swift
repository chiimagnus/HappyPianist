//
//  ImmersiveView.swift
//  LonelyPianistAVP
//
//  Created by chii_magnus on 2026/4/6.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var overlayController = PianoGuideOverlayController()

    var body: some View {
        ZStack {
            RealityView { content in
                // Add the initial RealityKit content
                if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                    content.add(immersiveContentEntity)
                }
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

            VStack(spacing: 12) {
                Text(currentStepSummary)
                Text(handTrackingSummary)
                    .font(.caption)
                HStack(spacing: 16) {
                    Button("Skip") {
                        appModel.practiceSessionViewModel.skip()
                    }
                    Button("Mark Correct") {
                        appModel.practiceSessionViewModel.markCorrect()
                    }
                }
                HStack(spacing: 8) {
                    Button("Tolerance -") {
                        appModel.practiceSessionViewModel.noteMatchTolerance = max(
                            0,
                            appModel.practiceSessionViewModel.noteMatchTolerance - 1
                        )
                    }
                    Text("Tolerance ±\(appModel.practiceSessionViewModel.noteMatchTolerance)")
                        .font(.caption)
                    Button("Tolerance +") {
                        appModel.practiceSessionViewModel.noteMatchTolerance = min(
                            2,
                            appModel.practiceSessionViewModel.noteMatchTolerance + 1
                        )
                    }
                }
            }
            .padding()
            .glassBackgroundEffect()
        }
        .onAppear {
            appModel.handTrackingService.start()
        }
        .onDisappear {
            appModel.handTrackingService.stop()
        }
    }

    private var currentStepSummary: String {
        guard let step = appModel.practiceSessionViewModel.currentStep else {
            return "No active step"
        }
        let summary = step.notes.map { midiToName($0.midiNote) }.joined(separator: " + ")
        return "Current Step: \(summary)"
    }

    private var handTrackingSummary: String {
        switch appModel.handTrackingService.state {
        case .idle:
            return "Hand tracking: idle"
        case .running:
            let pressed = appModel.practiceSessionViewModel.pressedNotes.sorted()
            return "Hand tracking: running (\(appModel.handTrackingService.fingerTipPositions.count) tips) | pressed: \(pressed)"
        case .unavailable(let reason):
            return "Hand tracking unavailable: \(reason). Use Mark Correct fallback."
        }
    }

    private func midiToName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = midi / 12 - 1
        let index = max(0, min(11, midi % 12))
        return "\(names[index])\(octave)"
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
