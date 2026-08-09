import MusicXML
import Practice
import simd

/// The authored bind skeleton shared by the pure clip builder and the packaged RealityKit rigs.
///
/// The values come from the checked-in Blender USD assets. Keeping this compact value snapshot
/// here lets the off-main builder validate the same local hierarchy that `jointTransforms` uses.
struct PianoDemonstrationHandSkeleton {
    struct Joint: Sendable {
        let translation: SIMD3<Float>
        let rotation: SIMD4<Float>
    }

    private static let parents: [Int?] = [
        nil,
        0, 1, 2, 3,
        0, 5, 6, 7,
        0, 9, 10, 11,
        0, 13, 14, 15,
        0, 17, 18, 19,
    ]

    private static let rightJoints: [Joint] = [
        .init(translation: [0, -0.045, 0], rotation: [0, 0, 0, 1]),
        .init(translation: [-0.030, 0.049, -0.004], rotation: [-0.0206863, 0, -0.2896085, 0.9569216]),
        .init(translation: [0, 0.0252587, 0], rotation: [0.0413946, -0.0095142, 0.1394095, 0.9893235]),
        .init(translation: [0, 0.0231084, 0], rotation: [0.0027161, -0.0027249, 0.1039048, 0.9945798]),
        .init(translation: [0, 0.0201246, 0], rotation: [0, 0, 0, 1]),
        .init(translation: [-0.016, 0.072, 0], rotation: [-0.0293642, 0, -0.0146821, 0.9994609]),
        .init(translation: [0, 0.0340735, 0], rotation: [0.0501664, -0.0003057, 0.0146789, 0.9986330]),
        .init(translation: [0, 0.0240208, 0], rotation: [0.0290090, 0, 0, 0.9995792]),
        .init(translation: [0, 0.0200997, 0], rotation: [0, 0, 0, 1]),
        .init(translation: [0, 0.076, 0.001], rotation: [-0.0256158, 0, 0, 0.9996719]),
        .init(translation: [0, 0.0390512, 0], rotation: [0.0441143, 0, 0, 0.9990265]),
        .init(translation: [0, 0.0270185, 0], rotation: [0.0463246, 0, 0, 0.9989265]),
        .init(translation: [0, 0.0231948, 0], rotation: [0, 0, 0, 1]),
        .init(translation: [0.017, 0.073, 0], rotation: [-0.0277377, 0, 0.0138688, 0.9995190]),
        .init(translation: [0, 0.0360694, 0], rotation: [0.0476931, 0.0008311, 0.0061032, 0.9988431]),
        .init(translation: [0, 0.02504, 0], rotation: [0.0298426, 0.0009951, -0.0199513, 0.9993550]),
        .init(translation: [0, 0.0200997, 0], rotation: [0, 0, 0, 1]),
        .init(translation: [0.033, 0.067, -0.001], rotation: [-0.0354946, 0, 0.0532418, 0.9979506]),
        .init(translation: [0, 0.0282312, 0], rotation: [0.0603746, 0.0022143, -0.0283065, 0.9977719]),
        .init(translation: [0, 0.0200499, 0], rotation: [0.0371161, 0.0007742, 0.0061114, 0.9992920]),
        .init(translation: [0, 0.0161555, 0], rotation: [0, 0, 0, 1]),
    ]

    static func jointPositions(
        hand: ScoreHand,
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>]
    ) -> [SIMD3<Float>]? {
        guard jointRotations.count == PianoHandMotionClip.jointCount,
              hand == .left || hand == .right
        else {
            return nil
        }
        let joints = restJoints(for: hand)
        let rootRotation = simd_quatf(vector: rootTransform.rotation)
        var positions: [SIMD3<Float>] = []
        var rotations: [simd_quatf] = []
        for index in joints.indices {
            let joint = joints[index]
            let localRotation = simd_quatf(vector: jointRotations[index])
                * simd_quatf(vector: joint.rotation)
            if let parent = parents[index] {
                guard positions.indices.contains(parent), rotations.indices.contains(parent) else { return nil }
                positions.append(positions[parent] + rotations[parent].act(joint.translation))
                rotations.append(rotations[parent] * localRotation)
            } else {
                positions.append(rootTransform.translation + rootRotation.act(joint.translation))
                rotations.append(rootRotation * localRotation)
            }
        }
        return positions.allSatisfy(Self.isFinite) ? positions : nil
    }

    static func fingerJointPositions(
        finger: Int,
        hand: ScoreHand,
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>]
    ) -> [SIMD3<Float>]? {
        guard (1 ... 5).contains(finger),
              let positions = jointPositions(
                  hand: hand,
                  rootTransform: rootTransform,
                  jointRotations: jointRotations
              )
        else {
            return nil
        }
        let start = 1 + (finger - 1) * 4
        return Array(positions[start ... start + 3])
    }

    static func fingerRootPosition(
        finger: Int,
        hand: ScoreHand,
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>]
    ) -> SIMD3<Float>? {
        fingerJointPositions(
            finger: finger,
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        )?.first
    }

    static func fingerSegmentLengths(_ finger: Int, hand: ScoreHand) -> [Float]? {
        let rotations = Array(repeating: SIMD4<Float>(0, 0, 0, 1), count: PianoHandMotionClip.jointCount)
        guard let joints = fingerJointPositions(
            finger: finger,
            hand: hand,
            rootTransform: .init(translation: .zero, rotation: [0, 0, 0, 1]),
            jointRotations: rotations
        )
        else {
            return nil
        }
        return zip(joints, joints.dropFirst()).map { simd_distance($0, $1) }
    }

    static func restJoints(for hand: ScoreHand) -> [Joint] {
        hand == .right ? rightJoints : rightJoints.map { joint in
            .init(
                translation: [-joint.translation.x, joint.translation.y, joint.translation.z],
                rotation: [joint.rotation.x, -joint.rotation.y, -joint.rotation.z, joint.rotation.w]
            )
        }
    }

    private static func isFinite(_ position: SIMD3<Float>) -> Bool {
        position.x.isFinite && position.y.isFinite && position.z.isFinite
    }
}
