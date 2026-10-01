import RealityKit
import simd
import SwiftUI

@MainActor
final class SpatialLibrarySceneController {
    let interactionEntity = Entity()

    private let rootEntity = Entity()
    private let metrics: SpatialBookDisplayMetrics
    private var hasAttachedRoot = false
    private var folioEntities: [UUID: ViewAttachmentEntity] = [:]
    private var spreadEntity: ViewAttachmentEntity?

    init(metrics: SpatialBookDisplayMetrics = .standard) {
        self.metrics = metrics

        rootEntity.name = "SpatialLibraryRoot"
        rootEntity.isEnabled = false

        interactionEntity.name = "SpatialLibraryBrowseInteraction"
        interactionEntity.position = SIMD3<Float>(0, 0, -metrics.browseSurfaceDepthMeters)
        interactionEntity.components.set(
            CollisionComponent(
                shapes: [
                    .generateBox(
                        size: SIMD3<Float>(1.25, 0.55, 0.02)
                    ),
                ]
            )
        )
        interactionEntity.components.set(
            InputTargetComponent(allowedInputTypes: .all)
        )
        rootEntity.addChild(interactionEntity)
    }

    func update(
        isActive: Bool,
        placement: SpatialLibraryPlacement?,
        visibleItems: [SpatialLibraryVisibleItem],
        showsSpread: Bool,
        browseDragProgress: CGFloat,
        attachments: RealityViewAttachments,
        content: RealityViewContent
    ) {
        attachRootIfNeeded(to: content)

        guard isActive, let placement else {
            rootEntity.isEnabled = false
            interactionEntity.isEnabled = false
            detachAttachments()
            return
        }

        rootEntity.isEnabled = true
        rootEntity.transform = Transform(matrix: placement.worldFromSpatialLibrary)
        interactionEntity.isEnabled = showsSpread == false && visibleItems.count > 1

        if showsSpread {
            detachFolios()
            attachSpread(from: attachments)
        } else {
            detachSpread()
            syncFolios(
                visibleItems: visibleItems,
                browseDragProgress: browseDragProgress,
                attachments: attachments
            )
        }
    }

    func reset() {
        rootEntity.isEnabled = false
        interactionEntity.isEnabled = false
        detachAttachments()
    }

    private func attachRootIfNeeded(to content: RealityViewContent) {
        guard hasAttachedRoot == false else { return }
        content.add(rootEntity)
        hasAttachedRoot = true
    }

    private func syncFolios(
        visibleItems: [SpatialLibraryVisibleItem],
        browseDragProgress: CGFloat,
        attachments: RealityViewAttachments
    ) {
        let expectedIDs = Set(visibleItems.map(\.id))

        for (id, entity) in folioEntities where expectedIDs.contains(id) == false {
            entity.removeFromParent()
            folioEntities[id] = nil
        }

        let dragOffsetMeters =
            Float(browseDragProgress) * metrics.folioSpacingMeters * 0.35

        for item in visibleItems {
            let attachmentID = SpatialLibraryAttachmentID.folio(item.id)
            guard let entity = attachments.entity(for: attachmentID) else { continue }

            if folioEntities[item.id] !== entity {
                folioEntities[item.id]?.removeFromParent()
                folioEntities[item.id] = entity
                rootEntity.addChild(entity)
            } else if entity.parent == nil {
                rootEntity.addChild(entity)
            }

            let presentation = LibraryBookFlowPresentation(
                signedDistance: CGFloat(item.relativeIndex)
            )
            entity.position = SIMD3<Float>(
                Float(item.relativeIndex) * metrics.folioSpacingMeters
                    + Float(presentation.lateralOffsetUnits) * metrics.folioSpacingMeters
                    + dragOffsetMeters,
                0,
                Float(presentation.depthOffsetUnits) * metrics.depthStepMeters
            )
            entity.orientation = simd_quatf(
                angle: Float(presentation.yawDegrees * .pi / 180),
                axis: SIMD3<Float>(0, 1, 0)
            )
            entity.components.set(
                OpacityComponent(opacity: Float(presentation.opacity))
            )
            applyPhysicalScale(
                to: entity,
                targetWidthMeters: metrics.folioWidthMeters,
                targetHeightMeters: metrics.effectiveFolioHeightMeters,
                presentationScale: Float(presentation.scale)
            )
        }
    }

    private func attachSpread(from attachments: RealityViewAttachments) {
        guard let entity = attachments.entity(for: SpatialLibraryAttachmentID.spread) else {
            return
        }

        if spreadEntity !== entity {
            spreadEntity?.removeFromParent()
            spreadEntity = entity
            rootEntity.addChild(entity)
        } else if entity.parent == nil {
            rootEntity.addChild(entity)
        }

        entity.position = SIMD3<Float>(0, 0, 0.06)
        entity.orientation = simd_quatf()
        entity.components.set(OpacityComponent(opacity: 1))
        applyPhysicalScale(
            to: entity,
            targetWidthMeters: metrics.spreadWidthMeters,
            targetHeightMeters: metrics.effectiveSpreadHeightMeters,
            presentationScale: 1
        )
    }

    private func applyPhysicalScale(
        to entity: ViewAttachmentEntity,
        targetWidthMeters: Float,
        targetHeightMeters: Float,
        presentationScale: Float
    ) {
        let renderedBounds = entity.visualBounds(
            recursive: true,
            relativeTo: entity
        ).extents

        guard let baseScale = metrics.uniformScale(
            renderedBounds: renderedBounds,
            targetWidthMeters: targetWidthMeters,
            targetHeightMeters: targetHeightMeters
        ) else {
            return
        }

        entity.scale = SIMD3<Float>(
            repeating: baseScale * presentationScale
        )
    }

    private func detachFolios() {
        for entity in folioEntities.values {
            entity.removeFromParent()
        }
        folioEntities.removeAll(keepingCapacity: true)
    }

    private func detachSpread() {
        spreadEntity?.removeFromParent()
        spreadEntity = nil
    }

    private func detachAttachments() {
        detachFolios()
        detachSpread()
    }
}
