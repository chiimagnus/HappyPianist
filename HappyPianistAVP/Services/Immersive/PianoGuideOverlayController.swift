import Foundation
import RealityKit
import SwiftUI
import UIKit

@MainActor
final class PianoGuideOverlayController {
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private var rootEntity = Entity()
    private var keyboardRootEntity = Entity()
    private var hasAttachedRoot = false
    private var activeBeamEntitiesByMIDINote: [Int: ModelEntity] = [:]
    private var activeDescriptorsByMIDINote: [Int: PianoGuideBeamDescriptor] = [:]
    private var lastGuideIDByMIDINote: [Int: Int] = [:]
    private var didAttemptDecalTextureLoad = false
    private var decalTextureLoadTask: Task<Void, Never>?
    private var decalTexture: TextureResource?
    private let restorationRenderer = PracticeRestorationEffectRenderer()

    init(diagnosticsReporter: (any DiagnosticsReporting)? = nil) {
        self.diagnosticsReporter = diagnosticsReporter
    }

    func updateHighlights(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
        differentiateWithoutColor: Bool,
        content: RealityViewContent
    ) {
        attachRootIfNeeded(to: content)
        startDecalTextureLoadIfNeeded()

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
        removeObsoleteBeams(desiredMIDINotes: desiredMIDINotes)

        for descriptor in descriptors {
            let beam = beamEntity(for: descriptor)
            activeDescriptorsByMIDINote[descriptor.midiNote] = descriptor
            configure(
                beam,
                descriptor: descriptor,
                differentiateWithoutColor: differentiateWithoutColor
            )
        }
    }

    func updateRestorationEffect(event: PracticeFeedbackEvent?, reduceMotion: Bool) {
        restorationRenderer.update(event: event, parent: keyboardRootEntity, reduceMotion: reduceMotion)
    }

    func reset() {
        decalTextureLoadTask?.cancel()
        decalTextureLoadTask = nil
        if decalTexture == nil {
            didAttemptDecalTextureLoad = false
        }
        clearBeams()
        restorationRenderer.reset()
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }

    private func attachRootIfNeeded(to content: RealityViewContent) {
        guard hasAttachedRoot == false else { return }
        content.add(rootEntity)
        rootEntity.addChild(keyboardRootEntity)
        hasAttachedRoot = true
    }

    private func removeObsoleteBeams(desiredMIDINotes: Set<Int>) {
        for (midiNote, beam) in activeBeamEntitiesByMIDINote where desiredMIDINotes.contains(midiNote) == false {
            beam.removeFromParent()
            activeBeamEntitiesByMIDINote[midiNote] = nil
            activeDescriptorsByMIDINote[midiNote] = nil
            lastGuideIDByMIDINote[midiNote] = nil
        }
    }

    private func beamEntity(for descriptor: PianoGuideBeamDescriptor) -> ModelEntity {
        if let existing = activeBeamEntitiesByMIDINote[descriptor.midiNote],
           lastGuideIDByMIDINote[descriptor.midiNote] == descriptor.guideID
        {
            return existing
        }

        activeBeamEntitiesByMIDINote[descriptor.midiNote]?.removeFromParent()
        let beam = ModelEntity(mesh: PianoGuideDecalMeshProvider.unitTopDecalMesh, materials: [])
        activeBeamEntitiesByMIDINote[descriptor.midiNote] = beam
        lastGuideIDByMIDINote[descriptor.midiNote] = descriptor.guideID
        keyboardRootEntity.addChild(beam)
        return beam
    }

    private func configure(
        _ beam: ModelEntity,
        descriptor: PianoGuideBeamDescriptor,
        differentiateWithoutColor: Bool
    ) {
        beam.model?.materials = [beamMaterial(for: descriptor)]

        var scale = descriptor.sizeLocal
        var position = descriptor.positionLocal
        if differentiateWithoutColor {
            scale.x *= 0.5
            let handOffset: Float = switch descriptor.hand {
            case .left: -0.25
            case .right: 0.25
            case .unknown: 0
            }
            position.x += descriptor.sizeLocal.x * handOffset
            if descriptor.phase == .triggered {
                scale.z *= 0.65
                position.z += descriptor.sizeLocal.z * 0.175
            }
        }

        beam.scale = scale
        beam.position = position
    }

    private func beamMaterial(for descriptor: PianoGuideBeamDescriptor) -> UnlitMaterial {
        let style = PianoGuideHighlightStyle.resolve(
            hand: descriptor.hand,
            phase: descriptor.phase,
            keyKind: descriptor.keyKind
        )
        let intensity = max(0, min(1, style.opacity))
        let tinted = style.tintToken.uiColor.scaledRGB(intensity: intensity)

        var material = UnlitMaterial()
        if let decalTexture {
            material.color = .init(tint: tinted, texture: .init(decalTexture))
        } else {
            material.color = .init(tint: tinted)
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }

    private func startDecalTextureLoadIfNeeded() {
        guard decalTexture == nil,
              decalTextureLoadTask == nil,
              didAttemptDecalTextureLoad == false
        else { return }

        didAttemptDecalTextureLoad = true
        decalTextureLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { decalTextureLoadTask = nil }

            do {
                let texture = try await TextureResource(named: "KeyDecalSoftRect")
                guard Task.isCancelled == false else {
                    didAttemptDecalTextureLoad = false
                    return
                }
                decalTexture = texture
                refreshActiveBeamMaterials()
            } catch is CancellationError {
                didAttemptDecalTextureLoad = false
            } catch {
                decalTexture = nil
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .immersiveSpace,
                    stage: "pianoGuide.loadTexture",
                    summary: "钢琴引导贴图加载失败",
                    reason: String(describing: error)
                )
            }
        }
    }

    private func refreshActiveBeamMaterials() {
        for (midiNote, descriptor) in activeDescriptorsByMIDINote {
            activeBeamEntitiesByMIDINote[midiNote]?.model?.materials = [beamMaterial(for: descriptor)]
        }
    }

    private func clearBeams() {
        for beam in activeBeamEntitiesByMIDINote.values {
            beam.removeFromParent()
        }
        activeBeamEntitiesByMIDINote.removeAll()
        activeDescriptorsByMIDINote.removeAll()
        lastGuideIDByMIDINote.removeAll()
    }
}
