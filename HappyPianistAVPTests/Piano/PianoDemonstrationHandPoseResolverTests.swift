@testable import HappyPianistAVP
import simd
import Testing

@Test
func poseResolverPlacesTargetedFingertipsOnKeyContacts() throws {
    let targets = [
        makeTarget(hand: .right, finger: .thumb, midiNote: 60, point: [0.10, 0, -0.07]),
        makeTarget(hand: .right, finger: .middle, midiNote: 64, point: [0.15, 0.006, -0.07]),
    ]

    let resolution = PianoDemonstrationHandPoseResolver().resolve(hand: .right, targets: targets)
    let pose = try #require(resolution.pose)

    let thumbTip = try #require(pose.fingerPose(for: .thumb)?.jointPositionsLocal.last)
    let middleTip = try #require(pose.fingerPose(for: .middle)?.jointPositionsLocal.last)
    #expect(simd_distance(thumbTip, targets[0].contactPositionLocal) < 0.0001)
    #expect(simd_distance(middleTip, targets[1].contactPositionLocal) < 0.0001)
    #expect(pose.fingers.allSatisfy { finger in
        finger.jointPositionsLocal.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    })
}

@Test
func poseResolverKeepsFingerRootsAttachedToTheAuthoredPalm() throws {
    let target = makeTarget(hand: .right, finger: .thumb, midiNote: 60, point: [0.10, 0, -0.07])
    let resolution = PianoDemonstrationHandPoseResolver().resolve(hand: .right, targets: [target])
    let pose = try #require(resolution.pose)
    let thumbRoot = try #require(pose.fingerPose(for: .thumb)?.jointPositionsLocal.first)
    let indexRoot = try #require(pose.fingerPose(for: .index)?.jointPositionsLocal.first)

    #expect(simd_distance(thumbRoot - pose.palmCenterLocal, [-0.030, -0.004, -0.004]) < 0.0001)
    #expect(simd_distance(indexRoot - pose.palmCenterLocal, [-0.016, 0, -0.027]) < 0.0001)
}

@Test
func poseResolverMirrorsUntargetedFingerSpread() throws {
    let rightTarget = makeTarget(hand: .right, finger: .middle, midiNote: 64, point: [0.12, 0, -0.07])
    let leftTarget = makeTarget(hand: .left, finger: .middle, midiNote: 52, point: [0.12, 0, -0.07])
    let resolver = PianoDemonstrationHandPoseResolver()

    let right = try #require(resolver.resolve(hand: .right, targets: [rightTarget]).pose)
    let left = try #require(resolver.resolve(hand: .left, targets: [leftTarget]).pose)
    let rightThumb = try #require(right.fingerPose(for: .thumb)?.jointPositionsLocal.first)
    let leftThumb = try #require(left.fingerPose(for: .thumb)?.jointPositionsLocal.first)

    #expect(rightThumb.x < right.palmCenterLocal.x)
    #expect(leftThumb.x > left.palmCenterLocal.x)
}

@Test
func poseResolverRejectsAnEmptyHand() {
    #expect(PianoDemonstrationHandPoseResolver().resolve(hand: .left, targets: []) == .empty)
}

@Test
func poseResolverLiftsTheWristAndStrikingFingerBeforeContact() throws {
    let target = makeTarget(hand: .right, finger: .index, midiNote: 64, point: [0.12, 0, -0.07])
    let resolver = PianoDemonstrationHandPoseResolver()

    let prepared = try #require(resolver.resolve(
        hand: .right,
        targets: [target],
        strikeProgressByOccurrenceID: [target.occurrenceID: 0]
    ).pose)
    let contact = try #require(resolver.resolve(
        hand: .right,
        targets: [target],
        strikeProgressByOccurrenceID: [target.occurrenceID: 1]
    ).pose)
    let preparedTip = try #require(prepared.fingerPose(for: .index)?.jointPositionsLocal.last)
    let contactTip = try #require(contact.fingerPose(for: .index)?.jointPositionsLocal.last)

    #expect(prepared.palmCenterLocal.y > contact.palmCenterLocal.y)
    #expect(preparedTip.y > contactTip.y)
    #expect(simd_distance(contactTip, target.contactPositionLocal) < 0.0001)
}

@Test
func poseResolverKeepsHeldFingerOnItsKeyWhileAnotherFingerStrikes() throws {
    let held = makeTarget(
        hand: .right,
        finger: .middle,
        midiNote: 64,
        point: [0.12, 0, -0.07],
        phase: .held
    )
    let triggered = makeTarget(
        hand: .right,
        finger: .index,
        midiNote: 67,
        point: [0.15, 0, -0.07]
    )

    let prepared = try #require(PianoDemonstrationHandPoseResolver().resolve(
        hand: .right,
        targets: [held, triggered],
        strikeProgressByOccurrenceID: [triggered.occurrenceID: 0]
    ).pose)
    let heldTip = try #require(prepared.fingerPose(for: .middle)?.jointPositionsLocal.last)
    let triggeredTip = try #require(prepared.fingerPose(for: .index)?.jointPositionsLocal.last)

    #expect(simd_distance(heldTip, held.contactPositionLocal) < 0.0001)
    #expect(triggeredTip.y > triggered.contactPositionLocal.y)
}

@Test
func poseResolverSamplesEachTriggeredOccurrenceIndependently() throws {
    let first = makeTarget(hand: .right, finger: .index, midiNote: 62, point: [0.11, 0, -0.07])
    let second = makeTarget(hand: .right, finger: .middle, midiNote: 64, point: [0.14, 0, -0.07])

    let pose = try #require(PianoDemonstrationHandPoseResolver().resolve(
        hand: .right,
        targets: [first, second],
        strikeProgressByOccurrenceID: [first.occurrenceID: 0, second.occurrenceID: 1]
    ).pose)
    let firstTip = try #require(pose.fingerPose(for: .index)?.jointPositionsLocal.last)
    let secondTip = try #require(pose.fingerPose(for: .middle)?.jointPositionsLocal.last)

    #expect(firstTip.y > first.contactPositionLocal.y)
    #expect(simd_distance(secondTip, second.contactPositionLocal) < 0.0001)
}

@Test
func poseResolverReturnsOnlyReachableTargetsAndTheirContactResiduals() throws {
    let reachableTargets = [
        makeTarget(hand: .right, finger: .thumb, midiNote: 60, point: [0.10, 0, -0.07]),
        makeTarget(hand: .right, finger: .index, midiNote: 61, point: [0.12, 0, -0.07]),
        makeTarget(hand: .right, finger: .middle, midiNote: 62, point: [0.14, 0, -0.07]),
        makeTarget(hand: .right, finger: .ring, midiNote: 63, point: [0.16, 0, -0.07]),
    ]
    let unreachableTarget = makeTarget(
        hand: .right,
        finger: .little,
        midiNote: 64,
        point: [0.18, 0, -0.40]
    )

    let resolution = PianoDemonstrationHandPoseResolver().resolve(
        hand: .right,
        targets: reachableTargets + [unreachableTarget]
    )
    let pose = try #require(resolution.pose)
    let unreachable = try #require(resolution.unreachableOccurrences.first)

    #expect(unreachable.occurrenceID == unreachableTarget.occurrenceID)
    #expect(unreachable.contactErrorMeters > PianoDemonstrationHandPoseResolver.maximumContactErrorMeters)
    #expect(resolution.reachableOccurrenceIDs == Set(reachableTargets.map(\.occurrenceID)))
    for target in reachableTargets {
        let tip = try #require(pose.fingerPose(for: target.finger)?.jointPositionsLocal.last)
        #expect(simd_distance(tip, target.contactPositionLocal) < 0.0001)
    }
}

private func makeTarget(
    hand: PianoDemonstrationHand,
    finger: PianoDemonstrationFinger,
    midiNote: Int,
    point: SIMD3<Float>,
    phase: PianoDemonstrationTouchPhase = .triggered
) -> PianoDemonstrationHandTarget {
    PianoDemonstrationHandTarget(
        occurrenceID: "\(hand)-\(midiNote)",
        hand: hand,
        finger: finger,
        midiNote: midiNote,
        phase: phase,
        contactPositionLocal: point,
        velocity: 96
    )
}
