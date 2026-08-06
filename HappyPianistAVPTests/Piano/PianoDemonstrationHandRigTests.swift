@testable import HappyPianistAVP
import RealityKit
import simd
import Testing

@MainActor
@Test
func handRigLoadsPackaged21JointAssetAndAppliesPose() async throws {
    let rig = try await PianoDemonstrationHandRig.load(hand: .right)
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
    ))

    #expect(rig.jointCount == 21)
    #expect(rig.rootEntity.children.count == 1)
    rig.apply(pose: pose)
    #expect(rig.rootEntity.isEnabled)
    #expect(simd_distance(rig.rootEntity.position, pose.palmCenterLocal) < 0.0001)

    rig.hide()
    #expect(rig.rootEntity.isEnabled == false)
}
