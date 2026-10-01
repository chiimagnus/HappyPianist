import RealityKit
import simd
import SwiftUI

@MainActor
final class SpatialLibrarySceneController {
    static let folioTransitionDuration: TimeInterval = 0.32

    let interactionEntity = Entity()

    private let rootEntity = Entity()
    private let metrics: SpatialBookDisplayMetrics
    private var hasAttachedRoot = false
    private var folioEntities: [UUID: ViewAttachmentEntity] = [:]
    private var spreadEntity: ViewAttachmentEntity?
    private var managementEntity: ViewAttachmentEntity?
    private var folioTargets: [UUID: Transform] = [:]
    private var folioMotions: [UUID: (entity: Entity, playback: AnimationPlaybackController)] = [:]

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
        attachManagement(from: attachments, showsSpread: showsSpread)

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
            stopFolioMotion(id)
            folioTargets[id] = nil
            entity.removeFromParent()
            folioEntities[id] = nil
        }

        let dragOffsetMeters =
            Float(browseDragProgress) * metrics.folioSpacingMeters * 0.35

        for item in visibleItems {
            let attachmentID = SpatialLibraryAttachmentID.folio(item.id)
            guard let entity = attachments.entity(for: attachmentID) else { continue }

            let isNewFolio = folioEntities[item.id] !== entity

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
            let position = SIMD3<Float>(
                Float(item.relativeIndex) * metrics.folioSpacingMeters
                    + Float(presentation.lateralOffsetUnits) * metrics.folioSpacingMeters
                    + dragOffsetMeters,
                0,
                Float(presentation.depthOffsetUnits) * metrics.depthStepMeters
            )
            let orientation = simd_quatf(
                angle: Float(presentation.yawDegrees * .pi / 180),
                axis: SIMD3<Float>(0, 1, 0)
            )
            entity.components.set(
                OpacityComponent(opacity: Float(presentation.opacity))
            )
            guard let scale = physicalScale(
                for: entity,
                targetWidthMeters: metrics.folioWidthMeters,
                targetHeightMeters: metrics.effectiveFolioHeightMeters,
                presentationScale: Float(presentation.scale)
            ) else { continue }
            moveFolio(
                entity,
                id: item.id,
                to: Transform(scale: scale, rotation: orientation, translation: position),
                immediately: isNewFolio || browseDragProgress != 0
            )
        }
    }

    func moveFolio(_ entity: Entity, id: UUID, to target: Transform, immediately: Bool) {
        if immediately {
            stopFolioMotion(id)
            entity.transform = target
            folioTargets[id] = target
            return
        }
        guard folioTargets[id] != target else { return }
        stopFolioMotion(id)
        folioTargets[id] = target
        let playback = entity.move(
            to: target,
            relativeTo: rootEntity,
            duration: Self.folioTransitionDuration,
            timingFunction: .easeInOut
        )
        folioMotions[id] = (entity, playback)
    }

    private func stopFolioMotion(_ id: UUID) {
        guard let motion = folioMotions.removeValue(forKey: id) else { return }
        let current = motion.entity.transform
        motion.playback.stop()
        motion.entity.transform = current
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

    private func attachManagement(from attachments: RealityViewAttachments, showsSpread: Bool) {
        guard let entity = attachments.entity(for: SpatialLibraryAttachmentID.management) else { return }
        if managementEntity !== entity {
            managementEntity?.removeFromParent()
            managementEntity = entity
            rootEntity.addChild(entity)
        } else if entity.parent == nil {
            rootEntity.addChild(entity)
        }
        let bookHeight = showsSpread ? metrics.effectiveSpreadHeightMeters : metrics.effectiveFolioHeightMeters
        entity.position = SIMD3<Float>(0, -bookHeight / 2 - 0.055, 0.06)
        applyPhysicalScale(
            to: entity,
            targetWidthMeters: 0.20,
            targetHeightMeters: 0.035,
            presentationScale: 1
        )
    }

    private func applyPhysicalScale(
        to entity: ViewAttachmentEntity,
        targetWidthMeters: Float,
        targetHeightMeters: Float,
        presentationScale: Float
    ) {
        guard let scale = physicalScale(
            for: entity,
            targetWidthMeters: targetWidthMeters,
            targetHeightMeters: targetHeightMeters,
            presentationScale: presentationScale
        ) else { return }
        entity.scale = scale
    }

    private func physicalScale(
        for entity: ViewAttachmentEntity,
        targetWidthMeters: Float,
        targetHeightMeters: Float,
        presentationScale: Float
    ) -> SIMD3<Float>? {
        let renderedBounds = entity.visualBounds(
            recursive: true,
            relativeTo: entity
        ).extents

        guard let baseScale = metrics.uniformScale(
            renderedBounds: renderedBounds,
            targetWidthMeters: targetWidthMeters,
            targetHeightMeters: targetHeightMeters
        ) else {
            return nil
        }

        return SIMD3<Float>(
            repeating: baseScale * presentationScale
        )
    }

    private func detachFolios() {
        for id in Array(folioMotions.keys) {
            stopFolioMotion(id)
        }
        folioTargets.removeAll(keepingCapacity: true)
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
        managementEntity?.removeFromParent()
        managementEntity = nil
    }
}
