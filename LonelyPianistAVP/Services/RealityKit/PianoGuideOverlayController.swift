import Foundation
import RealityKit
import SwiftUI

@MainActor
final class PianoGuideOverlayController {
    private var rootEntity = Entity()
    private var keyboardRootEntity = Entity()
    private var hasAttachedRoot = false
    private var activeMarkers: [Entity] = []

    func updateHighlights(
        currentStep: PracticeStep?,
        keyboardFrame: KeyboardFrame?,
        keyRegions: [PianoKeyRegion],
        feedbackState: PracticeSessionViewModel.VisualFeedbackState,
        content: RealityViewContent
    ) {
        if hasAttachedRoot == false {
            content.add(rootEntity)
            rootEntity.addChild(keyboardRootEntity)
            hasAttachedRoot = true
        }

        clearMarkers()
        guard let currentStep else { return }
        guard let keyboardFrame else { return }

        keyboardRootEntity.transform = Transform(matrix: keyboardFrame.worldFromKeyboard)

        let tintColor: UIColor = switch feedbackState {
            case .none:
                AVPOverlayPalette.feedbackNoneColor
            case .correct:
                AVPOverlayPalette.feedbackCorrectColor
            case .wrong:
                AVPOverlayPalette.feedbackWrongColor
        }

        let regionByNote = Dictionary(uniqueKeysWithValues: keyRegions.map { ($0.midiNote, $0) })
        for note in currentStep.notes {
            guard let region = regionByNote[note.midiNote] else { continue }

            // Convert world-space key region center to keyboard-local coordinates so markers inherit the
            // keyboard yaw from `keyboardRootEntity`.
            let centerWorld = SIMD4<Float>(region.center, 1)
            let centerLocal4 = simd_mul(keyboardFrame.keyboardFromWorld, centerWorld)
            let centerLocal = SIMD3<Float>(centerLocal4.x, centerLocal4.y, centerLocal4.z)

            let marker = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(region.size.x * 0.9, 0.01, region.size.z * 0.9)),
                materials: [SimpleMaterial(color: tintColor, isMetallic: false)]
            )
            marker.position = SIMD3<Float>(centerLocal.x, centerLocal.y + region.size.y * 0.6, centerLocal.z)
            keyboardRootEntity.addChild(marker)
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
