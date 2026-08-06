@testable import HappyPianistAVP
import simd
import Testing

@Test
func poseResolverPlacesTargetedFingertipsOnKeyContacts() throws {
    let targets = [
        makeTarget(hand: .right, finger: .thumb, midiNote: 60, point: [0.10, 0, -0.07]),
        makeTarget(hand: .right, finger: .middle, midiNote: 64, point: [0.15, 0.006, -0.07]),
    ]

    let pose = try #require(PianoDemonstrationHandPoseResolver().resolve(hand: .right, targets: targets))

    #expect(pose.fingerPose(for: .thumb)?.jointPositionsLocal.last == targets[0].contactPositionLocal)
    #expect(pose.fingerPose(for: .middle)?.jointPositionsLocal.last == targets[1].contactPositionLocal)
    #expect(pose.fingers.allSatisfy { finger in
        finger.jointPositionsLocal.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    })
}

@Test
func poseResolverMirrorsUntargetedFingerSpread() throws {
    let rightTarget = makeTarget(hand: .right, finger: .middle, midiNote: 64, point: [0.12, 0, -0.07])
    let leftTarget = makeTarget(hand: .left, finger: .middle, midiNote: 52, point: [0.12, 0, -0.07])
    let resolver = PianoDemonstrationHandPoseResolver()

    let right = try #require(resolver.resolve(hand: .right, targets: [rightTarget]))
    let left = try #require(resolver.resolve(hand: .left, targets: [leftTarget]))
    let rightThumb = try #require(right.fingerPose(for: .thumb)?.jointPositionsLocal.first)
    let leftThumb = try #require(left.fingerPose(for: .thumb)?.jointPositionsLocal.first)

    #expect(rightThumb.x < right.palmCenterLocal.x)
    #expect(leftThumb.x > left.palmCenterLocal.x)
}

@Test
func poseResolverRejectsAnEmptyHand() {
    #expect(PianoDemonstrationHandPoseResolver().resolve(hand: .left, targets: []) == nil)
}

private func makeTarget(
    hand: PianoDemonstrationHand,
    finger: PianoDemonstrationFinger,
    midiNote: Int,
    point: SIMD3<Float>
) -> PianoDemonstrationHandTarget {
    PianoDemonstrationHandTarget(
        occurrenceID: "\(hand)-\(midiNote)",
        hand: hand,
        finger: finger,
        midiNote: midiNote,
        phase: .triggered,
        contactPositionLocal: point,
        velocity: 96
    )
}
