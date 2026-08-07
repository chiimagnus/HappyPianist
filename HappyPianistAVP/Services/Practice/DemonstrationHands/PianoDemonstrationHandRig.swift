import RealityKit
import RealityKitContent
import simd
import SwiftUI
import UIKit

enum PianoDemonstrationHandRigError: Error {
    case missingSkinnedModel
    case invalidJointSet
}

@MainActor
protocol PianoDemonstrationHandRigLoading {
    func load(hand: PianoDemonstrationHand) async throws -> PianoDemonstrationHandRig
}

@MainActor
struct PackagedPianoDemonstrationHandRigLoader: PianoDemonstrationHandRigLoading {
    func load(hand: PianoDemonstrationHand) async throws -> PianoDemonstrationHandRig {
        try await PianoDemonstrationHandRig.load(hand: hand)
    }
}

@MainActor
final class PianoDemonstrationHandRig {
    let rootEntity: Entity

    private let modelEntity: ModelEntity
    private let restJointTransforms: [Transform]
    private let jointIndicesByFinger: [PianoDemonstrationFinger: [Int]]
    private let wristJointIndex: Int

    private init(
        rootEntity: Entity,
        modelEntity: ModelEntity,
        jointIndicesByFinger: [PianoDemonstrationFinger: [Int]],
        wristJointIndex: Int
    ) {
        self.rootEntity = rootEntity
        self.modelEntity = modelEntity
        restJointTransforms = modelEntity.jointTransforms
        self.jointIndicesByFinger = jointIndicesByFinger
        self.wristJointIndex = wristJointIndex
        rootEntity.isEnabled = false
    }

    static func load(hand: PianoDemonstrationHand) async throws -> PianoDemonstrationHandRig {
        let assetName = switch hand {
        case .left: "PianoDemonstrationHandLeft"
        case .right: "PianoDemonstrationHandRight"
        }
        let asset = try await Entity(named: assetName, in: realityKitContentBundle)
        guard let modelEntity = asset.firstSkinnedModelEntity() else {
            throw PianoDemonstrationHandRigError.missingSkinnedModel
        }

        let indicesByName = Dictionary(
            uniqueKeysWithValues: modelEntity.jointNames.enumerated().map { index, name in
                (name.split(separator: "/").last.map(String.init) ?? name, index)
            }
        )
        guard let wristJointIndex = indicesByName["wrist"] else {
            throw PianoDemonstrationHandRigError.invalidJointSet
        }

        var jointIndicesByFinger: [PianoDemonstrationFinger: [Int]] = [:]
        for finger in PianoDemonstrationFinger.allCases {
            let name = finger.jointName
            let indices = (0 ..< 4).compactMap { indicesByName["\(name)_\($0)"] }
            guard indices.count == 4 else {
                throw PianoDemonstrationHandRigError.invalidJointSet
            }
            jointIndicesByFinger[finger] = indices
        }
        guard modelEntity.jointNames.count == 21,
              modelEntity.jointTransforms.count == 21
        else {
            throw PianoDemonstrationHandRigError.invalidJointSet
        }

        modelEntity.model?.materials = [makeMaterial(for: hand)]
        let rootEntity = Entity()
        rootEntity.addChild(asset)
        return PianoDemonstrationHandRig(
            rootEntity: rootEntity,
            modelEntity: modelEntity,
            jointIndicesByFinger: jointIndicesByFinger,
            wristJointIndex: wristJointIndex
        )
    }

    var jointCount: Int {
        modelEntity.jointNames.count
    }

    func apply(pose: PianoDemonstrationHandPose) {
        rootEntity.stopAllAnimations()
        rootEntity.isEnabled = true
        rootEntity.transform = Transform(translation: pose.palmCenterLocal)

        var transforms = restJointTransforms
        guard wristJointIndex < transforms.count else { return }
        let wristRotation = transforms[wristJointIndex].rotation

        for fingerPose in pose.fingers {
            guard fingerPose.jointPositionsLocal.count == 4,
                  let jointIndices = jointIndicesByFinger[fingerPose.finger],
                  jointIndices.count == 4
            else {
                continue
            }

            let positions = fingerPose.jointPositionsLocal
            var parentRotationInHand = wristRotation
            for jointSlot in jointIndices.indices {
                let jointIndex = jointIndices[jointSlot]
                guard jointIndex < transforms.count else { continue }
                guard jointSlot + 1 < jointIndices.count else { continue }

                let childIndex = jointIndices[jointSlot + 1]
                guard childIndex < restJointTransforms.count else { continue }
                let desiredDirectionInModel = normalized(
                    modelEntity.convert(
                        direction: positions[jointSlot + 1] - positions[jointSlot],
                        from: rootEntity
                    )
                )
                let desiredDirectionInParent = parentRotationInHand.inverse.act(desiredDirectionInModel)
                let restChildTranslation = restJointTransforms[childIndex].translation
                let restDirectionInParent = normalized(
                    restJointTransforms[jointIndex].rotation.act(restChildTranslation)
                )
                let rotationDelta = simd_quatf(
                    from: restDirectionInParent,
                    to: desiredDirectionInParent
                )
                transforms[jointIndex].rotation = rotationDelta * restJointTransforms[jointIndex].rotation
                parentRotationInHand *= transforms[jointIndex].rotation
            }
        }
        modelEntity.jointTransforms = transforms
    }

    func lift(animated: Bool) {
        rootEntity.stopAllAnimations()
        rootEntity.isEnabled = true
        let liftedTransform = Transform(
            rotation: rootEntity.transform.rotation,
            translation: rootEntity.transform.translation + SIMD3<Float>(0, 0.035, 0)
        )
        guard animated else {
            rootEntity.transform = liftedTransform
            return
        }
        Entity.animate(.easeInOut(duration: 0.16)) {
            rootEntity.components.set(liftedTransform)
        }
    }

    func hide() {
        rootEntity.stopAllAnimations()
        rootEntity.isEnabled = false
    }

    private static func makeMaterial(for hand: PianoDemonstrationHand) -> PhysicallyBasedMaterial {
        let baseColor = switch hand {
        case .left: UIColor(red: 0.08, green: 0.78, blue: 1.00, alpha: 1)
        case .right: UIColor(red: 1.00, green: 0.72, blue: 0.16, alpha: 1)
        }
        let emissiveColor = switch hand {
        case .left: UIColor(red: 0.34, green: 0.42, blue: 1.00, alpha: 1)
        case .right: UIColor(red: 1.00, green: 0.30, blue: 0.22, alpha: 1)
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: baseColor)
        material.blending = .transparent(opacity: 0.58)
        material.sheen = .init(tint: .white)
        material.emissiveColor = .init(color: emissiveColor)
        material.emissiveIntensity = 1.15
        material.roughness = 0.22
        material.metallic = 0.06
        return material
    }

    private func normalized(_ value: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length > 0.0001 ? value / length : SIMD3<Float>(0, 0, -1)
    }
}

private extension PianoDemonstrationFinger {
    var jointName: String {
        switch self {
        case .thumb: "thumb"
        case .index: "index"
        case .middle: "middle"
        case .ring: "ring"
        case .little: "little"
        }
    }
}
