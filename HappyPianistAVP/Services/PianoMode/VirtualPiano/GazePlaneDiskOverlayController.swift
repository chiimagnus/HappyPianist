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
    private var textAttachmentEntity: Entity?
    private var lastStatusText: String?

    func update(
        isVisible: Bool,
        diskWorldTransform: simd_float4x4?,
        statusText: String?,
        cameraWorldPosition: SIMD3<Float>?,
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
            diskWorldTransform: diskWorldTransform,
            cameraWorldPosition: cameraWorldPosition
        )
    }

    func reset() {
        clearDisk()
        clearText()
        rootEntity.removeFromParent()
        hasAttachedRoot = false
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

        let attachmentEntity = Entity()
        attachmentEntity.isEnabled = false
        root.addChild(attachmentEntity)
        textAttachmentEntity = attachmentEntity
    }

    private func updateText(
        statusText: String?,
        diskWorldTransform: simd_float4x4,
        cameraWorldPosition: SIMD3<Float>?
    ) {
        guard let statusText, statusText.isEmpty == false else {
            clearText()
            return
        }

        if lastStatusText != statusText {
            lastStatusText = statusText
            updateTextAttachment(statusText: statusText)
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

        let awayFromCameraOnPlane: SIMD3<Float> = {
            guard let cameraWorldPosition else {
                return simd_normalize(SIMD3<Float>(
                    diskWorldTransform.columns.2.x,
                    diskWorldTransform.columns.2.y,
                    diskWorldTransform.columns.2.z
                ))
            }

            let toCamera = cameraWorldPosition - diskOrigin
            let toCameraOnPlane = toCamera - normal * simd_dot(toCamera, normal)
            if simd_length(toCameraOnPlane) < 1e-4 {
                return simd_normalize(SIMD3<Float>(
                    diskWorldTransform.columns.2.x,
                    diskWorldTransform.columns.2.y,
                    diskWorldTransform.columns.2.z
                ))
            }
            return -simd_normalize(toCameraOnPlane)
        }()

        let insetMeters: Float = 0.10
        let radiusMeters: Float = 0.23
        let alongPlaneMeters = max(0, radiusMeters - insetMeters)

        let worldPosition = diskOrigin + awayFromCameraOnPlane * alongPlaneMeters + normal * liftMeters
        textRootEntity.position = worldPosition
        textRootEntity.isEnabled = true
        textAttachmentEntity?.isEnabled = true
    }

    private func updateTextAttachment(statusText: String) {
        guard let textAttachmentEntity else { return }
        textAttachmentEntity.components.set(ViewAttachmentComponent(
            rootView: Text(statusText)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        ))
        textAttachmentEntity.scale = SIMD3<Float>(repeating: 0.55)
    }

    private func clearText() {
        textRootEntity?.isEnabled = false
        textAttachmentEntity?.isEnabled = false
        lastStatusText = nil
    }
}
