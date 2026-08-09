import RealityKit
import RealityKitContent
import Practice
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
    private static let expectedJointPathSuffixes = [
        "wrist",
        "thumb_0", "thumb_1", "thumb_2", "thumb_3",
        "index_0", "index_1", "index_2", "index_3",
        "middle_0", "middle_1", "middle_2", "middle_3",
        "ring_0", "ring_1", "ring_2", "ring_3",
        "little_0", "little_1", "little_2", "little_3",
    ]

    let rootEntity: Entity

    private let modelEntity: ModelEntity
    private let restJointTransforms: [Transform]

    private init(
        rootEntity: Entity,
        modelEntity: ModelEntity
    ) {
        self.rootEntity = rootEntity
        self.modelEntity = modelEntity
        restJointTransforms = modelEntity.jointTransforms
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

        let jointPathSuffixes = modelEntity.jointNames.map {
            $0.split(separator: "/").last.map(String.init) ?? ""
        }
        guard jointPathSuffixes == expectedJointPathSuffixes,
              modelEntity.jointTransforms.count == expectedJointPathSuffixes.count
        else {
            throw PianoDemonstrationHandRigError.invalidJointSet
        }

        modelEntity.model?.materials = [makeMaterial(for: hand)]
        let rootEntity = Entity()
        rootEntity.addChild(asset)
        return PianoDemonstrationHandRig(
            rootEntity: rootEntity,
            modelEntity: modelEntity
        )
    }

    var jointCount: Int {
        modelEntity.jointNames.count
    }

    func apply(frame: PianoHandMotionClip.Frame) {
        guard frame.jointRotations.count == restJointTransforms.count else { return }
        rootEntity.stopAllAnimations()
        rootEntity.isEnabled = true
        rootEntity.transform = Transform(
            rotation: simd_quatf(vector: frame.rootTransform.rotation),
            translation: frame.rootTransform.translation
        )

        var transforms = restJointTransforms
        for index in transforms.indices {
            transforms[index].rotation = simd_quatf(vector: frame.jointRotations[index])
                * restJointTransforms[index].rotation
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
}
