import RealityKit
import simd
import SwiftUI
import UIKit

@MainActor
final class GazePlaneDiskOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var diskEntity: ModelEntity?

    func update(
        isVisible: Bool,
        diskWorldTransform: simd_float4x4?,
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        guard isVisible, var diskWorldTransform else {
            clearDisk()
            return
        }

        ensureDiskIfNeeded()

        let normal = simd_normalize(SIMD3<Float>(
            diskWorldTransform.columns.1.x,
            diskWorldTransform.columns.1.y,
            diskWorldTransform.columns.1.z
        ))
        let offsetMeters: Float = 0.002
        diskWorldTransform.columns.3 = SIMD4<Float>(
            diskWorldTransform.columns.3.x + normal.x * offsetMeters,
            diskWorldTransform.columns.3.y + normal.y * offsetMeters,
            diskWorldTransform.columns.3.z + normal.z * offsetMeters,
            1
        )

        diskEntity?.transform = Transform(matrix: diskWorldTransform)
        diskEntity?.isEnabled = true
    }

    private func ensureDiskIfNeeded() {
        guard diskEntity == nil else { return }

        let radiusMeters: Float = 0.23
        let heightMeters: Float = 0.002

        let mesh = MeshResource.generateCylinder(height: heightMeters, radius: radiusMeters)
        let color = UIColor.systemGreen.withAlphaComponent(0.45)
        let material = UnlitMaterial(color: color)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.isEnabled = false
        rootEntity.addChild(entity)
        diskEntity = entity
    }

    private func clearDisk() {
        diskEntity?.isEnabled = false
    }
}
