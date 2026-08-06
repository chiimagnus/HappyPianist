import RealityKit
import simd
import SwiftUI
import UIKit

@MainActor
final class PianoDemonstrationHandRig {
    let rootEntity: Entity

    private let palmEntity: ModelEntity
    private let fingerSegments: [PianoDemonstrationFinger: [ModelEntity]]
    private let fingertipEntities: [PianoDemonstrationFinger: ModelEntity]

    init(rootEntity: Entity = Entity()) {
        self.rootEntity = rootEntity

        let material = Self.makeMaterial()
        let palmMesh = MeshResource.generateBox(size: SIMD3<Float>(repeating: 1))
        let segmentMesh = MeshResource.generateCylinder(height: 1, radius: 0.5)
        let fingertipMesh = MeshResource.generateSphere(radius: 0.5)
        let palm = ModelEntity(mesh: palmMesh, materials: [material])
        palmEntity = palm
        rootEntity.addChild(palm)

        var segmentsByFinger: [PianoDemonstrationFinger: [ModelEntity]] = [:]
        var tipsByFinger: [PianoDemonstrationFinger: ModelEntity] = [:]
        for finger in PianoDemonstrationFinger.allCases {
            let segments = (0 ..< 3).map { _ in
                let segment = ModelEntity(mesh: segmentMesh, materials: [material])
                rootEntity.addChild(segment)
                return segment
            }
            let fingertip = ModelEntity(mesh: fingertipMesh, materials: [material])
            rootEntity.addChild(fingertip)
            segmentsByFinger[finger] = segments
            tipsByFinger[finger] = fingertip
        }
        fingerSegments = segmentsByFinger
        fingertipEntities = tipsByFinger
        rootEntity.isEnabled = false
    }

    var renderedEntityCount: Int {
        1 + PianoDemonstrationFinger.allCases.count * 4
    }

    func apply(pose: PianoDemonstrationHandPose, animated: Bool) {
        if animated == false {
            rootEntity.stopAllAnimations()
        }
        let startsLifted = animated && rootEntity.isEnabled == false
        rootEntity.isEnabled = true
        if animated, rootEntity.transform.translation.y > 0.0001 {
            apply(.identity, to: rootEntity, animated: true)
        } else {
            rootEntity.transform = .identity
        }
        apply(
            Transform(
                scale: SIMD3<Float>(0.092, 0.018, 0.070),
                rotation: .init(),
                translation: pose.palmCenterLocal
            ),
            to: palmEntity,
            animated: animated,
            startsLifted: startsLifted
        )

        for fingerPose in pose.fingers {
            guard fingerPose.jointPositionsLocal.count == 4,
                  let segments = fingerSegments[fingerPose.finger],
                  let fingertip = fingertipEntities[fingerPose.finger]
            else {
                continue
            }

            var jointPositions = fingerPose.jointPositionsLocal
            jointPositions[3].y += fingertipRadius(for: fingerPose.finger)
            let animationDelay = animationDelay(for: fingerPose.finger)
            for index in segments.indices {
                apply(
                    segmentTransform(
                        from: jointPositions[index],
                        to: jointPositions[index + 1],
                        finger: fingerPose.finger
                    ),
                    to: segments[index],
                    animated: animated,
                    startsLifted: startsLifted,
                    delay: animationDelay
                )
            }
            apply(
                Transform(
                    scale: SIMD3<Float>(repeating: fingertipDiameter(for: fingerPose.finger)),
                    rotation: .init(),
                    translation: jointPositions[3]
                ),
                to: fingertip,
                animated: animated,
                startsLifted: startsLifted,
                delay: animationDelay
            )
        }
    }

    func lift(animated: Bool) {
        rootEntity.stopAllAnimations()
        rootEntity.isEnabled = true
        apply(
            Transform(translation: SIMD3<Float>(0, 0.035, 0)),
            to: rootEntity,
            animated: animated
        )
    }

    func hide() {
        rootEntity.stopAllAnimations()
        rootEntity.isEnabled = false
    }

    private func apply(
        _ transform: Transform,
        to entity: Entity,
        animated: Bool,
        startsLifted: Bool = false,
        delay: Double = 0
    ) {
        if startsLifted {
            var liftedTransform = transform
            liftedTransform.translation.y += 0.028
            entity.transform = liftedTransform
        }
        guard animated else {
            entity.transform = transform
            return
        }

        Entity.animate(.easeInOut(duration: 0.15).delay(delay)) {
            entity.components.set(transform)
        }
    }

    private func animationDelay(for finger: PianoDemonstrationFinger) -> Double {
        Double(finger.rawValue - PianoDemonstrationFinger.thumb.rawValue) * 0.008
    }

    private static func makeMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.98, green: 0.90, blue: 0.76, alpha: 1))
        material.blending = .transparent(opacity: 0.72)
        material.sheen = .init(tint: .white)
        material.roughness = 0.30
        material.metallic = 0.03
        return material
    }

    private func segmentTransform(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        finger: PianoDemonstrationFinger
    ) -> Transform {
        let vector = end - start
        let length = simd_length(vector)
        guard length > 0.0001 else {
            return Transform(
                scale: SIMD3<Float>(repeating: 0.001),
                rotation: .init(),
                translation: start
            )
        }

        return Transform(
            scale: SIMD3<Float>(segmentDiameter(for: finger), length, segmentDiameter(for: finger)),
            rotation: simd_quatf(from: SIMD3<Float>(0, 1, 0), to: vector / length),
            translation: (start + end) / 2
        )
    }

    private func segmentDiameter(for finger: PianoDemonstrationFinger) -> Float {
        switch finger {
        case .thumb: 0.018
        case .index, .middle: 0.016
        case .ring: 0.015
        case .little: 0.013
        }
    }

    private func fingertipDiameter(for finger: PianoDemonstrationFinger) -> Float {
        segmentDiameter(for: finger) * 1.12
    }

    private func fingertipRadius(for finger: PianoDemonstrationFinger) -> Float {
        fingertipDiameter(for: finger) / 2
    }
}
