import Foundation
import RealityKit
import SwiftUI

@MainActor
final class PianoGuideOverlayController {
    private var rootEntity = Entity()
    private var keyboardRootEntity = Entity()
    private var hasAttachedRoot = false
    private var activeBeamEntitiesByMIDINote: [Int: ModelEntity] = [:]
    private var lastGuideIDByMIDINote: [Int: Int] = [:]
    private var didAttemptAtlasTextureLoad = false
    private var atlasTexture: TextureResource?

    func updateHighlights(
        highlightGuide: PianoHighlightGuide?,
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
            highlightGuide: highlightGuide,
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
                lastGuideIDByMIDINote[midiNote] = nil
            }
        }

        for descriptor in descriptors {
            let beam: ModelEntity
            if let existing = activeBeamEntitiesByMIDINote[descriptor.midiNote],
               lastGuideIDByMIDINote[descriptor.midiNote] == descriptor.guideID
            {
                beam = existing
            } else {
                activeBeamEntitiesByMIDINote[descriptor.midiNote]?.removeFromParent()
                beam = ModelEntity(mesh: PianoGuideBeamMeshFactory.unitPrismShellMesh, materials: [])
                activeBeamEntitiesByMIDINote[descriptor.midiNote] = beam
                lastGuideIDByMIDINote[descriptor.midiNote] = descriptor.guideID
                keyboardRootEntity.addChild(beam)
            }

            beam.model?.materials = [beamMaterial(for: descriptor)]
            beam.scale = descriptor.sizeLocal
            beam.position = descriptor.positionLocal
        }
    }

    private func beamMaterial(for descriptor: PianoGuideBeamDescriptor) -> UnlitMaterial {
        let tintColor: UIColor = switch descriptor.baseColor {
            case .guide:
                AVPOverlayPalette.feedbackNoneColor
            case .correct:
                AVPOverlayPalette.feedbackCorrectColor
            case .wrong:
                AVPOverlayPalette.feedbackWrongColor
        }
        let tinted = tintColor.withAlphaComponent(CGFloat(descriptor.alpha))
        let texture = loadAtlasTextureIfNeeded()

        var material = UnlitMaterial()
        if let texture {
            material.color = .init(tint: tinted, texture: .init(texture))
        } else {
            material.color = .init(tint: tinted)
        }
        return material
    }

    private func clearBeams() {
        for beam in activeBeamEntitiesByMIDINote.values {
            beam.removeFromParent()
        }
        activeBeamEntitiesByMIDINote.removeAll()
        lastGuideIDByMIDINote.removeAll()
    }

    private func loadAtlasTextureIfNeeded() -> TextureResource? {
        if didAttemptAtlasTextureLoad {
            return atlasTexture
        }

        didAttemptAtlasTextureLoad = true
        atlasTexture = try? TextureResource.load(named: "KeyBeamFourSideAtlas")
        return atlasTexture
    }
}
