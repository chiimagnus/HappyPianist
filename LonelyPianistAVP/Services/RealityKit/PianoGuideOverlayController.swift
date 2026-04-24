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

        guard let currentStep, let keyboardFrame else {
            clearMarkers()
            return
        }

        keyboardRootEntity.transform = Transform(matrix: keyboardFrame.worldFromKeyboard)

        let tintColor: UIColor = switch feedbackState {
            case .none:
                AVPOverlayPalette.feedbackNoneColor
            case .correct:
                AVPOverlayPalette.feedbackCorrectColor
            case .wrong:
                AVPOverlayPalette.feedbackWrongColor
        }

        if lastTintColor != tintColor {
            let material = SimpleMaterial(color: tintColor, isMetallic: false)
            for marker in activeMarkersByMIDINote.values {
                marker.model?.materials = [material]
            }
            lastTintColor = tintColor
        }

        let regionByNote = Dictionary(uniqueKeysWithValues: keyRegions.map { ($0.midiNote, $0) })
        let desiredNotes: Set<Int> = Set(currentStep.notes.map(\.midiNote))

        // Remove markers that are no longer needed.
        for (midiNote, marker) in activeMarkersByMIDINote {
            if desiredNotes.contains(midiNote) == false {
                marker.removeFromParent()
                activeMarkersByMIDINote[midiNote] = nil
            }
        }

        // Add/update markers for desired notes.
        for midiNote in desiredNotes {
            guard let region = regionByNote[midiNote] else { continue }

            // Convert world-space key region center to keyboard-local coordinates so markers inherit the
            // keyboard yaw from `keyboardRootEntity`.
            let centerWorld = SIMD4<Float>(region.center, 1)
            let centerLocal4 = simd_mul(keyboardFrame.keyboardFromWorld, centerWorld)
            let centerLocal = SIMD3<Float>(centerLocal4.x, centerLocal4.y, centerLocal4.z)

            let marker: ModelEntity
            if let existing = activeMarkersByMIDINote[midiNote] {
                marker = existing
            } else {
                marker = ModelEntity(
                    mesh: .generateBox(size: SIMD3<Float>(region.size.x * 0.9, 0.01, region.size.z * 0.9)),
                    materials: [SimpleMaterial(color: tintColor, isMetallic: false)]
                )
                activeMarkersByMIDINote[midiNote] = marker
                keyboardRootEntity.addChild(marker)
            }
            marker.position = SIMD3<Float>(centerLocal.x, centerLocal.y, centerLocal.z)
        }
    }

    private func clearMarkers() {
        for marker in activeMarkersByMIDINote.values {
            marker.removeFromParent()
        }
        activeMarkersByMIDINote.removeAll()
        lastTintColor = nil
    }
}
