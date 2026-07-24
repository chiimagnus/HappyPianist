import RealityKit
import simd

struct XiaochengRig {
    let modelEntity: ModelEntity
    let restJointTransforms: [Transform]
    let leftArmJointIndices: [Int]
    let rightArmJointIndices: [Int]
    let leftLegJointIndices: [Int]
    let rightLegJointIndices: [Int]
    let neckJointIndex: Int?
    let headJointIndex: Int?
}

enum XiaochengRigBuilder {
    @MainActor
    static func makeRig(modelEntity: ModelEntity) -> XiaochengRig? {
        let jointNames = modelEntity.jointNames
        guard jointNames.isEmpty == false else { return nil }

        func index(endsWith component: String) -> Int? {
            jointNames.firstIndex { $0 == component || $0.hasSuffix("/\(component)") }
        }

        func index(endsWithAny components: [String]) -> Int? {
            guard components.isEmpty == false else { return nil }
            return jointNames.firstIndex { name in
                components.contains { component in
                    name == component
                        || name.hasSuffix("/\(component)")
                        || name.hasSuffix(":\(component)")
                        || name.hasSuffix(".\(component)")
                        || name.hasSuffix("_\(component)")
                        || name.hasSuffix(component)
                }
            }
        }

        let leftIndices = [
            index(endsWith: "LeftShoulder"),
            index(endsWith: "LeftArm"),
            index(endsWith: "LeftForeArm"),
        ].compactMap(\.self)
        let rightIndices = [
            index(endsWith: "RightShoulder"),
            index(endsWith: "RightArm"),
            index(endsWith: "RightForeArm"),
        ].compactMap(\.self)
        guard leftIndices.isEmpty == false || rightIndices.isEmpty == false else { return nil }

        let leftLegIndices = [
            index(endsWithAny: ["LeftUpLeg", "LeftThigh"]),
            index(endsWithAny: ["LeftLeg", "LeftCalf", "LeftShin"]),
            index(endsWithAny: ["LeftFoot"]),
            index(endsWithAny: ["LeftToeBase", "LeftToe"]),
        ].compactMap(\.self)
        let rightLegIndices = [
            index(endsWithAny: ["RightUpLeg", "RightThigh"]),
            index(endsWithAny: ["RightLeg", "RightCalf", "RightShin"]),
            index(endsWithAny: ["RightFoot"]),
            index(endsWithAny: ["RightToeBase", "RightToe"]),
        ].compactMap(\.self)

        let neckIndex = index(endsWith: "Neck")
        let headIndex = index(endsWith: "Head")

        var restTransforms = modelEntity.jointTransforms
        applyForwardRaisedArmsPose(jointNames: jointNames, jointTransforms: &restTransforms)
        modelEntity.jointTransforms = restTransforms

        return XiaochengRig(
            modelEntity: modelEntity,
            restJointTransforms: restTransforms,
            leftArmJointIndices: leftIndices,
            rightArmJointIndices: rightIndices,
            leftLegJointIndices: leftLegIndices,
            rightLegJointIndices: rightLegIndices,
            neckJointIndex: neckIndex,
            headJointIndex: headIndex
        )
    }

    private static func applyForwardRaisedArmsPose(
        jointNames: [String],
        jointTransforms: inout [Transform]
    ) {
        func index(endsWith component: String) -> Int? {
            jointNames.firstIndex { $0 == component || $0.hasSuffix("/\(component)") }
        }

        func apply(arm: String, foreArm: String) {
            guard let armIndex = index(endsWith: arm),
                  let foreArmIndex = index(endsWith: foreArm),
                  armIndex < jointTransforms.count,
                  foreArmIndex < jointTransforms.count
            else {
                return
            }

            let foreArmTranslation = jointTransforms[foreArmIndex].translation
            let foreArmLength = simd_length(foreArmTranslation)
            guard foreArmLength > 0.0001 else { return }

            let localArmDirection = foreArmTranslation / foreArmLength
            let currentArmDirection = jointTransforms[armIndex].rotation.act(localArmDirection)

            let desiredArmDirection = simd_normalize(SIMD3<Float>(0, 0, -1))
            let delta = simd_quatf(from: currentArmDirection, to: desiredArmDirection)
            jointTransforms[armIndex].rotation = delta * jointTransforms[armIndex].rotation
        }

        apply(arm: "LeftArm", foreArm: "LeftForeArm")
        apply(arm: "RightArm", foreArm: "RightForeArm")
    }
}

enum XiaochengPoseService {
    @MainActor
    static func applyHeadNodPose(rig: XiaochengRig, headNodAngleRadians: Float) {
        guard headNodAngleRadians != 0 else {
            rig.modelEntity.jointTransforms = baseTransforms(rig: rig, headNodAngleRadians: 0)
            return
        }

        var transforms = rig.modelEntity.jointTransforms
        let rest = rig.restJointTransforms

        let headRotation = simd_quatf(angle: headNodAngleRadians, axis: [1, 0, 0])
        let neckRotation = simd_quatf(angle: headNodAngleRadians * 0.35, axis: [1, 0, 0])

        if let neckIndex = rig.neckJointIndex, neckIndex < transforms.count, neckIndex < rest.count {
            transforms[neckIndex].rotation = rest[neckIndex].rotation * neckRotation
        }
        if let headIndex = rig.headJointIndex, headIndex < transforms.count, headIndex < rest.count {
            transforms[headIndex].rotation = rest[headIndex].rotation * headRotation
        }

        rig.modelEntity.jointTransforms = transforms
    }

    static func baseTransforms(rig: XiaochengRig, headNodAngleRadians: Float) -> [Transform] {
        var transforms = rig.restJointTransforms
        applyHeadNodToBaseTransforms(angleRadians: headNodAngleRadians, rig: rig, jointTransforms: &transforms)
        return transforms
    }

    private static func applyHeadNodToBaseTransforms(
        angleRadians: Float,
        rig: XiaochengRig,
        jointTransforms: inout [Transform]
    ) {
        guard angleRadians != 0 else { return }

        let headRotation = simd_quatf(angle: angleRadians, axis: [1, 0, 0])
        if let neckIndex = rig.neckJointIndex, neckIndex < jointTransforms.count {
            jointTransforms[neckIndex].rotation = jointTransforms[neckIndex].rotation * simd_quatf(
                angle: angleRadians * 0.35,
                axis: [1, 0, 0]
            )
        }
        if let headIndex = rig.headJointIndex, headIndex < jointTransforms.count {
            jointTransforms[headIndex].rotation = jointTransforms[headIndex].rotation * headRotation
        }
    }
}
