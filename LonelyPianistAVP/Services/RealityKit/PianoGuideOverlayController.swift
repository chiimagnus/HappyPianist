import Foundation
import RealityKit
import SwiftUI

@MainActor
final class PianoGuideOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var activeMarkers: [Entity] = []

    func updateHighlights(
        currentStep: PracticeStep?,
        keyRegions: [PianoKeyRegion],
        feedbackState: PracticeSessionViewModel.VisualFeedbackState,
        content: RealityViewContent
    ) {
        if hasAttachedRoot == false {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        clearMarkers()
        guard let currentStep else { return }

        let tintColor: UIColor
        switch feedbackState {
        case .none:
            tintColor = AVPOverlayPalette.feedbackNoneColor
        case .correct:
            tintColor = AVPOverlayPalette.feedbackCorrectColor
        case .wrong:
            tintColor = AVPOverlayPalette.feedbackWrongColor
        }

        let regionByNote = Dictionary(uniqueKeysWithValues: keyRegions.map { ($0.midiNote, $0) })
        for note in currentStep.notes {
            guard let region = regionByNote[note.midiNote] else { continue }
            let marker = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(region.size.x * 0.9, 0.01, region.size.z * 0.9)),
                materials: [SimpleMaterial(color: tintColor, isMetallic: false)]
            )
            marker.position = SIMD3<Float>(region.center.x, region.center.y + region.size.y * 0.6, region.center.z)
            rootEntity.addChild(marker)
            activeMarkers.append(marker)
        }
    }

    private func clearMarkers() {
        for marker in activeMarkers {
            marker.removeFromParent()
        }
        activeMarkers.removeAll()
    }
}
