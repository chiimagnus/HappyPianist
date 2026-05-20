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
    private var didAttemptDecalTextureLoad = false
    private var decalTexture: TextureResource?

    func updateHighlights(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
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
            keyboardGeometry: keyboardGeometry
        )
        guard descriptors.isEmpty == false else {
            clearBeams()
            return
        }

        let desiredMIDINotes = Set(descriptors.map(\.midiNote))

        for (midiNote, beam) in activeBeamEntitiesByMIDINote {
            if desiredMIDINotes.contains(midiNote) == false {
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
                beam = ModelEntity(mesh: PianoGuideDecalMeshProvider.unitTopDecalMesh, materials: [])
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
        let tintColor = (descriptor.hand == .left) ? AVPOverlayPalette.leftHandGuideColor : AVPOverlayPalette.rightHandGuideColor
        let tinted = tintColor.withAlphaComponent(CGFloat(max(0, min(1, descriptor.alpha))))
        let texture = loadDecalTextureIfNeeded()

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

    private func loadDecalTextureIfNeeded() -> TextureResource? {
        if didAttemptDecalTextureLoad {
            return decalTexture
        }

        didAttemptDecalTextureLoad = true
        decalTexture = try? TextureResource.load(named: "KeyDecalSoftRect")
        return decalTexture
    }
}
