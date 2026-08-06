import RealityKit
@testable import HappyPianistAVP
import simd
import Testing

@MainActor
@Test
func handRigCreatesAndReusesItsFixedPrimitiveEntities() throws {
    let rig = PianoDemonstrationHandRig()
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

    #expect(rig.rootEntity.children.count == rig.renderedEntityCount)
    rig.apply(pose: pose)
    #expect(rig.rootEntity.isEnabled)
    #expect(rig.rootEntity.children.count == rig.renderedEntityCount)
    let middleTip = Array(rig.rootEntity.children)[12]
    #expect(abs(middleTip.position.y - 0.00896) < 0.0001)

    rig.hide()
    #expect(rig.rootEntity.isEnabled == false)
}
