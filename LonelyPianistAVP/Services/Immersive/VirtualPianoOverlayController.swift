import RealityKit
import simd
import SwiftUI

@MainActor
final class VirtualPianoOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var keyboardRootEntity: Entity?

    func update(
        isEnabled: Bool,
        keyboardGeometry: PianoKeyboardGeometry?,
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        guard isEnabled, let keyboardGeometry else {
            clearKeyboard()
            return
        }

        showKeyboard(geometry: keyboardGeometry)
    }

    private func showKeyboard(geometry: PianoKeyboardGeometry) {
        guard keyboardRootEntity == nil else { return }

        let totalLength = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
        let keyDepth = VirtualPianoKeyGeometryService.whiteKeyDepthMeters
        let keyboardCenterLocal = SIMD3<Float>(totalLength / 2, 0, -keyDepth / 2)

        let worldFromKeyboard = geometry.frame.worldFromKeyboard
        let xAxisWorld = SIMD3<Float>(worldFromKeyboard.columns.0.x, worldFromKeyboard.columns.0.y, worldFromKeyboard.columns.0.z)
        let yAxisWorld = SIMD3<Float>(worldFromKeyboard.columns.1.x, worldFromKeyboard.columns.1.y, worldFromKeyboard.columns.1.z)
        let zAxisWorld = SIMD3<Float>(worldFromKeyboard.columns.2.x, worldFromKeyboard.columns.2.y, worldFromKeyboard.columns.2.z)
        let originWorld = SIMD3<Float>(worldFromKeyboard.columns.3.x, worldFromKeyboard.columns.3.y, worldFromKeyboard.columns.3.z)
        let centerWorld = originWorld
            + xAxisWorld * keyboardCenterLocal.x
            + yAxisWorld * keyboardCenterLocal.y
            + zAxisWorld * keyboardCenterLocal.z

        var kbWorldFromCenter = worldFromKeyboard
        kbWorldFromCenter.columns.3 = SIMD4<Float>(centerWorld, 1)

        let kbRoot = Entity()
        kbRoot.transform = Transform(matrix: kbWorldFromCenter)

        let kbContent = Entity()
        kbContent.position = -keyboardCenterLocal

        for key in geometry.keys {
            let keyEntity = makeKeyEntity(for: key)
            kbContent.addChild(keyEntity)
        }

        kbRoot.addChild(kbContent)

        rootEntity.addChild(kbRoot)
        keyboardRootEntity = kbRoot

        animateKeyboardIn(kbRoot)
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

    private func animateKeyboardIn(_ keyboardRoot: Entity) {
        let endTransform = keyboardRoot.transform
        var startTransform = endTransform
        startTransform.scale = SIMD3<Float>(0.001, 1, 1)
        keyboardRoot.transform = startTransform
        _ = keyboardRoot.move(
            to: endTransform,
            relativeTo: keyboardRoot.parent,
            duration: 0.35,
            timingFunction: .easeOut
        )
    }
}
