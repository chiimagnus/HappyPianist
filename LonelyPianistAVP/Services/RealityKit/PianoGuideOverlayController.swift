import Foundation
import RealityKit
import SwiftUI

@MainActor
final class PianoGuideOverlayController {
    private var rootEntity = Entity()
    private var keyboardRootEntity = Entity()
    private var hasAttachedRoot = false
    private var activeMarkersByMIDINote: [Int: ModelEntity] = [:]
    private var lastTintColor: UIColor?

    private let lightBeamHeight: Float = 0.22
    private let lightBeamBaseYOffset: Float = 0.006
    private let lightBeamRadiusScale: Float = 0.32
    private let lightBeamMinimumRadius: Float = 0.006
    private let lightBeamAlpha: CGFloat = 0.42

    func updateHighlights(
        currentStep: PracticeStep?,
        keyboardGeometry: PianoKeyboardGeometry?,
        feedbackState: PracticeSessionViewModel.VisualFeedbackState,
        content: RealityViewContent
    ) {
        if hasAttachedRoot == false {
            content.add(rootEntity)
            rootEntity.addChild(keyboardRootEntity)
            hasAttachedRoot = true
        }

        guard let currentStep, let keyboardGeometry else {
            clearMarkers()
            return
        }

        keyboardRootEntity.transform = Transform(matrix: keyboardGeometry.frame.worldFromKeyboard)

        let tintColor: UIColor = switch feedbackState {
            case .none:
                AVPOverlayPalette.feedbackNoneColor
            case .correct:
                AVPOverlayPalette.feedbackCorrectColor
            case .wrong:
                AVPOverlayPalette.feedbackWrongColor
        }

        if lastTintColor != tintColor {
            let material = lightBeamMaterial(for: tintColor)
            for marker in activeMarkersByMIDINote.values {
                marker.model?.materials = [material]
            }
            lastTintColor = tintColor
        }

        let desiredNotes: Set<Int> = Set(currentStep.notes.map(\.midiNote))

        // Remove markers that are no longer needed.
        for (midiNote, marker) in activeMarkersByMIDINote {
            if desiredNotes.contains(midiNote) == false {
                marker.removeFromParent()
                activeMarkersByMIDINote[midiNote] = nil
            }
        }

        // Add/update light beams for desired notes.
        for midiNote in desiredNotes {
            guard let key = keyboardGeometry.key(for: midiNote) else { continue }

            let marker: ModelEntity
            if let existing = activeMarkersByMIDINote[midiNote] {
                marker = existing
            } else {
                marker = ModelEntity(
                    mesh: .generateCylinder(height: 1, radius: 1),
                    materials: [lightBeamMaterial(for: tintColor)]
                )
                activeMarkersByMIDINote[midiNote] = marker
                keyboardRootEntity.addChild(marker)
            }

            let keyFootprint = min(key.beamFootprintSizeLocal.x, key.beamFootprintSizeLocal.y)
            let beamRadius = max(keyFootprint * lightBeamRadiusScale, lightBeamMinimumRadius)
            marker.scale = SIMD3<Float>(beamRadius, lightBeamHeight, beamRadius)
            marker.position = SIMD3<Float>(
                key.beamFootprintCenterLocal.x,
                key.surfaceLocalY + lightBeamBaseYOffset + lightBeamHeight * 0.5,
                key.beamFootprintCenterLocal.z
            )
        }
    }

    private func lightBeamMaterial(for tintColor: UIColor) -> SimpleMaterial {
        SimpleMaterial(color: tintColor.withAlphaComponent(lightBeamAlpha), isMetallic: false)
    }

    private func clearMarkers() {
        for marker in activeMarkersByMIDINote.values {
            marker.removeFromParent()
        }
        activeMarkersByMIDINote.removeAll()
        lastTintColor = nil
    }
}
