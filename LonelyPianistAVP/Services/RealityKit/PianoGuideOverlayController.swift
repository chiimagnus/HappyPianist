import Foundation
import RealityKit
import SwiftUI

@MainActor
final class PianoGuideOverlayController {
    private var rootEntity = Entity()
    private var keyboardRootEntity = Entity()
    private var hasAttachedRoot = false
    private var activeBeamEntitiesByMIDINote: [Int: ModelEntity] = [:]

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

        guard let keyboardGeometry else {
            clearBeams()
            return
        }

        keyboardRootEntity.transform = Transform(matrix: keyboardGeometry.frame.worldFromKeyboard)

        let descriptors = PianoGuideBeamDescriptor.makeDescriptors(
            currentStep: currentStep,
            keyboardGeometry: keyboardGeometry,
            feedbackState: feedbackState
        )
        guard descriptors.isEmpty == false else {
            clearBeams()
            return
        }

        let desiredNotes = Set(descriptors.map(\.midiNote))

        for (midiNote, beam) in activeBeamEntitiesByMIDINote {
            if desiredNotes.contains(midiNote) == false {
                beam.removeFromParent()
                activeBeamEntitiesByMIDINote[midiNote] = nil
            }
        }

        for descriptor in descriptors {
            let beam: ModelEntity
            if let existing = activeBeamEntitiesByMIDINote[descriptor.midiNote] {
                beam = existing
            } else {
                beam = ModelEntity(mesh: PianoGuideBeamMeshFactory.unitPrismShellMesh, materials: [])
                activeBeamEntitiesByMIDINote[descriptor.midiNote] = beam
                keyboardRootEntity.addChild(beam)
            }

            beam.model?.materials = [beamMaterial(for: descriptor)]
            beam.scale = descriptor.sizeLocal
            beam.position = descriptor.positionLocal
        }
    }

    private func beamMaterial(for descriptor: PianoGuideBeamDescriptor) -> SimpleMaterial {
        let tintColor: UIColor = switch descriptor.baseColor {
            case .guide:
                AVPOverlayPalette.feedbackNoneColor
            case .correct:
                AVPOverlayPalette.feedbackCorrectColor
            case .wrong:
                AVPOverlayPalette.feedbackWrongColor
        }
        return SimpleMaterial(color: tintColor.withAlphaComponent(CGFloat(descriptor.alpha)), isMetallic: false)
    }

    private func clearBeams() {
        for beam in activeBeamEntitiesByMIDINote.values {
            beam.removeFromParent()
        }
        activeBeamEntitiesByMIDINote.removeAll()
    }
}
