import simd

struct PianoDemonstrationFingerPose: Equatable {
    let finger: PianoDemonstrationFinger
    let jointPositionsLocal: [SIMD3<Float>]
}

struct PianoDemonstrationHandPose: Equatable {
    let hand: PianoDemonstrationHand
    let wristPositionLocal: SIMD3<Float>
    let palmCenterLocal: SIMD3<Float>
    let fingers: [PianoDemonstrationFingerPose]

    func fingerPose(for finger: PianoDemonstrationFinger) -> PianoDemonstrationFingerPose? {
        fingers.first { $0.finger == finger }
    }
}

struct PianoDemonstrationHandPoseResolver {
    func resolve(
        hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget]
    ) -> PianoDemonstrationHandPose? {
        guard targets.isEmpty == false else { return nil }

        var targetByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget] = [:]
        for target in targets where target.hand == hand {
            targetByFinger[target.finger] = target
        }
        guard targetByFinger.isEmpty == false else { return nil }

        let targetPositions = targetByFinger.values.map(\.contactPositionLocal)
        let palmCenter = makePalmCenter(hand: hand, targetsByFinger: targetByFinger)
        let fingers = PianoDemonstrationFinger.allCases.map { finger in
            makeFingerPose(
                finger: finger,
                hand: hand,
                palmCenter: palmCenter,
                target: targetByFinger[finger]
            )
        }
        let wristPosition = palmCenter + SIMD3<Float>(0, -0.017, 0.047)

        guard targetPositions.allSatisfy(Self.isFinite),
              Self.isFinite(palmCenter),
              Self.isFinite(wristPosition)
        else {
            return nil
        }

        return PianoDemonstrationHandPose(
            hand: hand,
            wristPositionLocal: wristPosition,
            palmCenterLocal: palmCenter,
            fingers: fingers
        )
    }

    private func makePalmCenter(
        hand: PianoDemonstrationHand,
        targetsByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget]
    ) -> SIMD3<Float> {
        let palmX = targetsByFinger.reduce(into: Float.zero) { partial, item in
            partial += item.value.contactPositionLocal.x - fingerOffsetX(item.key, hand: hand)
        } / Float(targetsByFinger.count)
        let averageZ = targetsByFinger.values.reduce(into: Float.zero) { partial, target in
            partial += target.contactPositionLocal.z
        } / Float(targetsByFinger.count)
        let surfaceY = targetsByFinger.values.map(\.contactPositionLocal.y).max() ?? 0

        return SIMD3<Float>(palmX, surfaceY + 0.052, averageZ + 0.060)
    }

    private func makeFingerPose(
        finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand,
        palmCenter: SIMD3<Float>,
        target: PianoDemonstrationHandTarget?
    ) -> PianoDemonstrationFingerPose {
        let knuckle = palmCenter + SIMD3<Float>(
            fingerOffsetX(finger, hand: hand),
            finger == .thumb ? -0.009 : 0,
            finger == .thumb ? -0.004 : -0.019
        )
        let tip = target?.contactPositionLocal ?? naturalTip(
            finger: finger,
            hand: hand,
            palmCenter: palmCenter
        )
        let arch: Float = finger == .thumb ? 0.004 : 0.010
        let firstJoint = interpolated(knuckle, tip, progress: 0.34)
            + SIMD3<Float>(0, arch, 0.004)
        let secondJoint = interpolated(knuckle, tip, progress: 0.70)
            + SIMD3<Float>(0, arch * 0.58, 0.002)

        return PianoDemonstrationFingerPose(
            finger: finger,
            jointPositionsLocal: [knuckle, firstJoint, secondJoint, tip]
        )
    }

    private func naturalTip(
        finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand,
        palmCenter: SIMD3<Float>
    ) -> SIMD3<Float> {
        palmCenter + SIMD3<Float>(
            fingerOffsetX(finger, hand: hand),
            finger == .thumb ? -0.032 : -0.036,
            finger == .thumb ? -0.062 : -0.094
        )
    }

    private func fingerOffsetX(
        _ finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand
    ) -> Float {
        let rightHandOffsets: [PianoDemonstrationFinger: Float] = [
            .thumb: -0.031,
            .index: -0.016,
            .middle: 0,
            .ring: 0.017,
            .little: 0.033,
        ]
        let offset = rightHandOffsets[finger] ?? 0
        return hand == .right ? offset : -offset
    }

    private func interpolated(
        _ start: SIMD3<Float>,
        _ end: SIMD3<Float>,
        progress: Float
    ) -> SIMD3<Float> {
        start + (end - start) * progress
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
