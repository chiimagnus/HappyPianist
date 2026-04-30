import Foundation
import RealityKit
import simd
import SwiftUI

@MainActor
final class VirtualPianoOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var reticleEntity: ModelEntity?
    private var keyboardRootEntity: Entity?

    func update(
        placementState: VirtualPianoPlacementViewModel.PlacementState,
        keyboardGeometry: PianoKeyboardGeometry?,
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        switch placementState {
            case .disabled:
                clearReticle()
                clearKeyboard()

            case let .placing(reticlePoint):
                clearKeyboard()
                if let reticlePoint {
                    showReticle(at: reticlePoint)
                } else {
                    clearReticle()
                }

            case .placed:
                clearReticle()
                if let keyboardGeometry {
                    showKeyboard(geometry: keyboardGeometry)
                }
        }
    }

    private func showReticle(at point: SIMD3<Float>) {
        let reticle: ModelEntity
        if let existing = reticleEntity {
            reticle = existing
        } else {
            let mesh = MeshResource.generateSphere(radius: 0.015)
            let material = SimpleMaterial(color: .white.withAlphaComponent(0.8), isMetallic: false)
            reticle = ModelEntity(mesh: mesh, materials: [material])
            rootEntity.addChild(reticle)
            reticleEntity = reticle
        }
        reticle.position = point
    }

    private func clearReticle() {
        reticleEntity?.removeFromParent()
        reticleEntity = nil
    }

    private func showKeyboard(geometry: PianoKeyboardGeometry) {
        guard keyboardRootEntity == nil else { return }

        let kbRoot = Entity()
        kbRoot.transform = Transform(matrix: geometry.frame.worldFromKeyboard)

        for key in geometry.keys {
            let keyEntity = makeKeyEntity(for: key)
            kbRoot.addChild(keyEntity)
        }

        let totalLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
        let keyDepth = VirtualPianoKeyGeometryService.whiteKeyDepthMeters
        let collisionSize = SIMD3<Float>(totalLength, 0.05, keyDepth)
        let collisionCenter = SIMD3<Float>(totalLength / 2, -0.01, keyDepth / 2)
        let collisionShape = ShapeResource.generateBox(size: collisionSize)
            .offsetBy(translation: collisionCenter)
        kbRoot.components.set(CollisionComponent(shapes: [collisionShape]))
        kbRoot.components.set(InputTargetComponent())
        kbRoot.components.set(ManipulationComponent())

        rootEntity.addChild(kbRoot)
        keyboardRootEntity = kbRoot
    }

    private func clearKeyboard() {
        keyboardRootEntity?.removeFromParent()
        keyboardRootEntity = nil
    }

    private func makeKeyEntity(for key: PianoKeyGeometry) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: key.localSize)
        let color: UIColor = key.kind == .white ? .white : .black
        var material = SimpleMaterial(color: color, isMetallic: false)
        material.roughness = 0.5

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = key.localCenter
        return entity
    }

    func currentKeyboardWorldFromKeyboard() -> simd_float4x4? {
        keyboardRootEntity?.transform.matrix
    }
}
