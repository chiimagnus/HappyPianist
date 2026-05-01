import RealityKit
import simd
import SwiftUI

@MainActor
final class VirtualPianoOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var tableAnchorEntity: AnchorEntity?
    private var glowOrbEntities: [ModelEntity] = []
    private var keyboardRootEntity: Entity?

    func update(
        placementState: VirtualPianoTablePlacementViewModel.State,
        keyboardGeometry: PianoKeyboardGeometry?,
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        switch placementState {
            case .disabled:
                clearGlowOrbs()
                clearKeyboard()
                clearTableAnchor()

            case .waitingForTableAnchor:
                ensureTableAnchor()
                clearKeyboard()
                clearGlowOrbs()

            case .waitingForHandsStable:
                ensureTableAnchor()
                clearKeyboard()
                if tableAnchorEntity?.isAnchored == true {
                    showGlowOrbsIfNeeded()
                } else {
                    clearGlowOrbs()
                }

            case .ready:
                clearGlowOrbs()
                if let keyboardGeometry {
                    showKeyboard(geometry: keyboardGeometry)
                } else {
                    clearKeyboard()
                }

            case .failed:
                ensureTableAnchor()
                clearKeyboard()
                if tableAnchorEntity?.isAnchored == true {
                    showGlowOrbsIfNeeded()
                } else {
                    clearGlowOrbs()
                }
        }
    }

    private func ensureTableAnchor() {
        guard tableAnchorEntity == nil else { return }
        let anchor = AnchorEntity(
            .plane(.horizontal, classification: .table, minimumBounds: [0.3, 0.3]),
            trackingMode: .continuous
        )
        rootEntity.addChild(anchor)
        tableAnchorEntity = anchor
    }

    private func clearTableAnchor() {
        tableAnchorEntity?.removeFromParent()
        tableAnchorEntity = nil
    }

    private func showGlowOrbsIfNeeded() {
        guard glowOrbEntities.isEmpty else { return }
        guard let tableAnchorEntity else { return }

        let mesh = MeshResource.generateSphere(radius: 0.02)
        let material = SimpleMaterial(color: UIColor.systemCyan.withAlphaComponent(0.75), isMetallic: false)
        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-0.08, 0.01, 0.00),
            SIMD3<Float>(0.00, 0.01, 0.00),
            SIMD3<Float>(0.08, 0.01, 0.00),
        ]

        glowOrbEntities = positions.map { position in
            let orb = ModelEntity(mesh: mesh, materials: [material])
            orb.position = position
            tableAnchorEntity.addChild(orb)
            return orb
        }
    }

    private func clearGlowOrbs() {
        for orb in glowOrbEntities {
            orb.removeFromParent()
        }
        glowOrbEntities.removeAll(keepingCapacity: true)
    }

    private func showKeyboard(geometry: PianoKeyboardGeometry) {
        guard keyboardRootEntity == nil else { return }

        let kbRoot = Entity()
        kbRoot.transform = Transform(matrix: geometry.frame.worldFromKeyboard)

        for key in geometry.keys {
            let keyEntity = makeKeyEntity(for: key)
            kbRoot.addChild(keyEntity)
        }

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

    func currentTableWorldFromAnchor() -> simd_float4x4? {
        guard let tableAnchorEntity else { return nil }
        guard tableAnchorEntity.isAnchored else { return nil }
        return tableAnchorEntity.transformMatrix(relativeTo: nil)
    }
}
