import RealityKit
import simd
import SwiftUI
import UIKit

@MainActor
final class GazePlaneDiskOverlayController {
    private var rootEntity = Entity()
    private var hasAttachedRoot = false
    private var diskEntity: ModelEntity?
    private var textRootEntity: Entity?
    private var textEntity: ModelEntity?
    private var lastStatusText: String?

    func update(
        isVisible: Bool,
        diskWorldTransform: simd_float4x4?,
        statusText: String?,
        content: RealityViewContent?
    ) {
        if hasAttachedRoot == false, let content {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        guard isVisible, var diskWorldTransform else {
            clearDisk()
            clearText()
            return
        }

        ensureDiskIfNeeded()
        ensureTextIfNeeded()

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

        updateText(
            statusText: statusText,
            diskWorldTransform: diskWorldTransform
        )
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

    private func ensureTextIfNeeded() {
        guard textRootEntity == nil else { return }

        let root = Entity()
        root.components.set(BillboardComponent())
        root.isEnabled = false
        rootEntity.addChild(root)
        textRootEntity = root
    }

    private func updateText(
        statusText: String?,
        diskWorldTransform: simd_float4x4
    ) {
        guard let statusText, statusText.isEmpty == false else {
            clearText()
            return
        }

        if lastStatusText != statusText {
            lastStatusText = statusText
            updateTextMesh(statusText: statusText)
        }

        guard let textRootEntity else { return }

        let normal = simd_normalize(SIMD3<Float>(
            diskWorldTransform.columns.1.x,
            diskWorldTransform.columns.1.y,
            diskWorldTransform.columns.1.z
        ))
        let diskOrigin = SIMD3<Float>(
            diskWorldTransform.columns.3.x,
            diskWorldTransform.columns.3.y,
            diskWorldTransform.columns.3.z
        )

        let liftMeters: Float = 0.08
        let worldPosition = diskOrigin + normal * liftMeters
        textRootEntity.position = worldPosition
        textRootEntity.isEnabled = true
        textEntity?.isEnabled = true
    }

    private func updateTextMesh(statusText: String) {
        let font = UIFont.systemFont(ofSize: 0.07, weight: .semibold)
        let mesh = MeshResource.generateText(
            statusText,
            extrusionDepth: 0.001,
            font: font,
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )

        let entity: ModelEntity
        if let existing = textEntity {
            entity = existing
            entity.model?.mesh = mesh
        } else {
            entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor.white)])
            entity.position = .zero
            textRootEntity?.addChild(entity)
            textEntity = entity
        }
    }

    private func clearText() {
        textRootEntity?.isEnabled = false
        textEntity?.isEnabled = false
        lastStatusText = nil
    }
}
