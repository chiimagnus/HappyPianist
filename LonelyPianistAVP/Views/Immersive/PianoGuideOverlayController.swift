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
    private var lastTriggerTimestampByMIDINote: [Int: TimeInterval] = [:]
    private var lastTriggerGuideIDByMIDINote: [Int: Int] = [:]
    private var didAttemptAtlasTextureLoad = false
    private var atlasTexture: TextureResource?

    private let pulseDurationSeconds: TimeInterval = 0.22
    private let pulseScaleBoost: Float = 0.22
    private let pulseAlphaBoost: Float = 0.55

    func updateHighlights(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
        feedbackState: PracticeSessionViewModel.VisualFeedbackState,
        isAutoplayEnabled: Bool,
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

        if isAutoplayEnabled == false {
            lastTriggerTimestampByMIDINote.removeAll()
            lastTriggerGuideIDByMIDINote.removeAll()
        } else if let highlightGuide, highlightGuide.triggeredNotes.isEmpty == false {
            let now = ProcessInfo.processInfo.systemUptime
            for note in highlightGuide.triggeredNotes {
                if lastTriggerGuideIDByMIDINote[note.midiNote] != highlightGuide.id {
                    lastTriggerGuideIDByMIDINote[note.midiNote] = highlightGuide.id
                    lastTriggerTimestampByMIDINote[note.midiNote] = now
                }
            }
        }

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
        let now = ProcessInfo.processInfo.systemUptime

        for (midiNote, beam) in activeBeamEntitiesByMIDINote {
            if desiredNotes.contains(midiNote) == false {
                beam.removeFromParent()
                activeBeamEntitiesByMIDINote[midiNote] = nil
                lastGuideIDByMIDINote[midiNote] = nil
                lastTriggerTimestampByMIDINote[midiNote] = nil
                lastTriggerGuideIDByMIDINote[midiNote] = nil
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

            let pulse = pulseIntensity(for: descriptor.midiNote, now: now)
            beam.model?.materials = [beamMaterial(for: descriptor, pulse: pulse)]
            var scale = descriptor.sizeLocal
            let boost = max(0, min(1, pulse)) * pulseScaleBoost
            scale.x *= (1 + boost)
            scale.z *= (1 + boost)
            beam.scale = scale
            beam.position = descriptor.positionLocal
        }
    }

    private func pulseIntensity(for midiNote: Int, now: TimeInterval) -> Float {
        guard let triggeredAt = lastTriggerTimestampByMIDINote[midiNote] else { return 0 }
        let elapsed = now - triggeredAt
        guard elapsed >= 0, elapsed < pulseDurationSeconds else { return 0 }
        let t = Float(elapsed / pulseDurationSeconds)
        let remaining = 1 - t
        return remaining * remaining
    }

    private func beamMaterial(for descriptor: PianoGuideBeamDescriptor, pulse: Float) -> UnlitMaterial {
        let tintColor: UIColor = switch descriptor.baseColor {
            case .guide:
                AVPOverlayPalette.feedbackNoneColor
            case .correct:
                AVPOverlayPalette.feedbackCorrectColor
            case .wrong:
                AVPOverlayPalette.feedbackWrongColor
        }
        let pulsedAlpha = max(0, min(1, descriptor.alpha + max(0, min(1, pulse)) * pulseAlphaBoost))
        let tinted = tintColor.withAlphaComponent(CGFloat(pulsedAlpha))
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
        lastTriggerTimestampByMIDINote.removeAll()
        lastTriggerGuideIDByMIDINote.removeAll()
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
