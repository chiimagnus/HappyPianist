import RealityKit
import SwiftUI

@MainActor
final class CalibrationOverlayController {
    private let rootEntity = Entity()
    private var hasAttachedRoot = false

    private var reticleEntity: ModelEntity?
    private var a0Entity: ModelEntity?
    private var c8Entity: ModelEntity?

    func update(
        reticlePoint: SIMD3<Float>,
        isReticleReadyToConfirm: Bool,
        a0TrackedAnchorPoint: SIMD3<Float>?,
        c8TrackedAnchorPoint: SIMD3<Float>?,
        content: RealityViewContent
    ) {
        if hasAttachedRoot == false {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        let reticleColor = isReticleReadyToConfirm ? AVPOverlayPalette.reticleReadyColor : AVPOverlayPalette
            .reticleColor
        let reticle = ensureSphere(&reticleEntity, color: reticleColor, radius: 0.012)
        reticle.position = reticlePoint

        if let a0TrackedAnchorPoint {
            let a0 = ensureSphere(&a0Entity, color: AVPOverlayPalette.a0AnchorColor, radius: 0.01)
            a0.position = a0TrackedAnchorPoint
        } else {
            a0Entity?.removeFromParent()
            a0Entity = nil
        }

        if let c8TrackedAnchorPoint {
            let c8 = ensureSphere(&c8Entity, color: AVPOverlayPalette.c8AnchorColor, radius: 0.01)
            c8.position = c8TrackedAnchorPoint
        } else {
            c8Entity?.removeFromParent()
            c8Entity = nil
        }
    }

    private func ensureSphere(
        _ entity: inout ModelEntity?,
        color: UIColor,
        radius: Float
    ) -> ModelEntity {
        if let entity {
            entity.model?.materials = [UnlitMaterial(color: color)]
            return entity
        }

        let model = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [UnlitMaterial(color: color)]
        )
        rootEntity.addChild(model)
        entity = model
        return model
    }
}
