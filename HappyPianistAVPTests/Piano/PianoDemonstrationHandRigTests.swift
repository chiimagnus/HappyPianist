@testable import HappyPianistAVP
@testable import Practice
import RealityKit
import simd
import Testing

@MainActor
@Test
func handRigLoadsPackaged21JointAssetAndAppliesPose() async throws {
    let rig = try await PackagedPianoDemonstrationHandRigLoader().load(hand: .right)
    let pose = try #require(PianoDemonstrationHandPoseResolver().resolve(
        hand: .right,
        targets: [
            PianoDemonstrationHandTarget(
                occurrenceID: "middle",
                hand: .right,
                finger: .middle,
                midiNote: 64,
                phase: .triggered,
                contactPositionLocal: [0.12, 0, -0.07],
                velocity: 96
            ),
        ]
    ).pose)

    #expect(rig.jointCount == 21)
    #expect(rig.rootEntity.children.count == 1)
    let skinnedModel = try #require(rig.rootEntity.firstSkinnedModelEntity())
    let restTranslations = skinnedModel.jointTransforms.map(\.translation)
    rig.apply(pose: pose)
    #expect(rig.rootEntity.isEnabled)
    #expect(simd_distance(rig.rootEntity.position, pose.rootTransform.translation) < 0.0001)
    #expect(abs(simd_dot(
        rig.rootEntity.transform.rotation.vector,
        pose.rootTransform.rotation
    )) > 0.999)
    #expect(zip(restTranslations, skinnedModel.jointTransforms.map(\.translation)).allSatisfy {
        simd_distance($0, $1) < 0.000_001
    })

    rig.hide()
    #expect(rig.rootEntity.isEnabled == false)
}
