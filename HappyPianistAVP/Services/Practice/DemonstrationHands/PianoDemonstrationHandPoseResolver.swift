import Foundation
import simd

struct PianoDemonstrationFingerPose: Equatable {
    let finger: PianoDemonstrationFinger
    let jointPositionsLocal: [SIMD3<Float>]
}

struct PianoDemonstrationHandPose: Equatable {
    let hand: PianoDemonstrationHand
    let palmCenterLocal: SIMD3<Float>
    let fingers: [PianoDemonstrationFingerPose]

    func fingerPose(for finger: PianoDemonstrationFinger) -> PianoDemonstrationFingerPose? {
        fingers.first { $0.finger == finger }
    }
}

struct PianoDemonstrationHandPoseResolver {
    func resolve(
        hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget],
        strikeProgress: Float = 1
    ) -> PianoDemonstrationHandPose? {
        guard targets.isEmpty == false else { return nil }

        var targetByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget] = [:]
        for target in targets where target.hand == hand {
            targetByFinger[target.finger] = target
        }
        guard targetByFinger.isEmpty == false else { return nil }

        let targetPositions = targetByFinger.values.map(\.contactPositionLocal)
        let clampedStrikeProgress = min(1, max(0, strikeProgress))
        let palmCenter = makePalmCenter(
            hand: hand,
            targetsByFinger: targetByFinger,
            strikeProgress: clampedStrikeProgress
        )
        let fingers = PianoDemonstrationFinger.allCases.map { finger in
            makeFingerPose(
                finger: finger,
                hand: hand,
                palmCenter: palmCenter,
                target: targetByFinger[finger],
                strikeProgress: clampedStrikeProgress
            )
        }
        guard targetPositions.allSatisfy(Self.isFinite),
              Self.isFinite(palmCenter)
        else {
            return nil
        }

        return PianoDemonstrationHandPose(
            hand: hand,
            palmCenterLocal: palmCenter,
            fingers: fingers
        )
    }

    private func makePalmCenter(
        hand: PianoDemonstrationHand,
        targetsByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget],
        strikeProgress: Float
    ) -> SIMD3<Float> {
        let palmX = targetsByFinger.reduce(into: Float.zero) { partial, item in
            partial += item.value.contactPositionLocal.x - fingerOffsetX(item.key, hand: hand)
        } / Float(targetsByFinger.count)
        let averageZ = targetsByFinger.values.reduce(into: Float.zero) { partial, target in
            partial += target.contactPositionLocal.z
        } / Float(targetsByFinger.count)
        let surfaceY = targetsByFinger.values.map(\.contactPositionLocal.y).max() ?? 0

        return SIMD3<Float>(
            palmX,
            surfaceY + 0.052 + (1 - strikeProgress) * 0.012,
            averageZ + 0.060 + (1 - strikeProgress) * 0.004
        )
    }

    private func makeFingerPose(
        finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand,
        palmCenter: SIMD3<Float>,
        target: PianoDemonstrationHandTarget?,
        strikeProgress: Float
    ) -> PianoDemonstrationFingerPose {
        let knuckle = palmCenter + SIMD3<Float>(
            fingerOffsetX(finger, hand: hand),
            finger == .thumb ? -0.009 : 0,
            finger == .thumb ? -0.004 : -0.019
        )
        let tip: SIMD3<Float>
        if let target {
            let velocity = Float(target.velocity) / 127
            let strikeLift = target.phase == .triggered
                ? (1 - strikeProgress) * (0.018 + velocity * 0.008)
                : 0
            tip = target.contactPositionLocal + SIMD3<Float>(0, strikeLift, 0)
        } else {
            tip = naturalTip(finger: finger, hand: hand, palmCenter: palmCenter)
        }
        let joints = solveFingerChain(
            root: knuckle,
            tip: tip,
            segmentLengths: segmentLengths(for: finger),
            archHeight: finger == .thumb ? 0.006 : 0.013
        )

        return PianoDemonstrationFingerPose(
            finger: finger,
            jointPositionsLocal: joints
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

    private func segmentLengths(for finger: PianoDemonstrationFinger) -> [Float] {
        // ponytail: these three lengths match the Blender-authored 21-joint rig.
        switch finger {
        case .thumb: [0.02526, 0.02311, 0.02012]
        case .index: [0.03407, 0.02402, 0.02010]
        case .middle: [0.03905, 0.02702, 0.02322]
        case .ring: [0.03607, 0.02504, 0.02012]
        case .little: [0.02818, 0.02002, 0.01616]
        }
    }

    private func solveFingerChain(
        root: SIMD3<Float>,
        tip: SIMD3<Float>,
        segmentLengths: [Float],
        archHeight: Float
    ) -> [SIMD3<Float>] {
        guard segmentLengths.count == 3 else { return [root, root, root, tip] }
        let totalLength = segmentLengths.reduce(0, +)
        let initialRootToTip = tip - root
        let initialDistance = simd_length(initialRootToTip)
        let direction = normalized(initialRootToTip, fallback: [0, -1, 0])
        let solvedRoot = initialDistance < totalLength * 0.97
            ? root
            : tip - direction * totalLength * 0.97

        let vertical = SIMD3<Float>(0, 1, 0)
        let archDirection = normalized(
            vertical - direction * simd_dot(vertical, direction),
            fallback: [0, 0, 1]
        )
        var joints = [
            solvedRoot,
            solvedRoot + direction * segmentLengths[0] + archDirection * archHeight,
            solvedRoot + direction * (segmentLengths[0] + segmentLengths[1]) + archDirection * archHeight * 0.72,
            tip,
        ]

        for _ in 0 ..< 10 {
            joints[3] = tip
            for index in stride(from: 2, through: 0, by: -1) {
                let towardParent = normalized(joints[index] - joints[index + 1], fallback: -direction)
                joints[index] = joints[index + 1] + towardParent * segmentLengths[index]
            }
            joints[0] = solvedRoot
            for index in 0 ..< 3 {
                let towardChild = normalized(joints[index + 1] - joints[index], fallback: direction)
                joints[index + 1] = joints[index] + towardChild * segmentLengths[index]
            }
        }
        return joints
    }

    private func normalized(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length > 0.0001 ? value / length : fallback
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}

struct PianoDemonstrationStrikeTimeline {
    struct Sample: Equatable {
        let contactProgress: Float
        let isComplete: Bool
    }

    func sample(elapsed: TimeInterval, velocity: UInt8) -> Sample {
        let normalizedVelocity = Float(velocity) / 127
        let anticipationDuration = 0.085
        let attackDuration = 0.155 - TimeInterval(normalizedVelocity) * 0.035
        let reboundDuration = 0.065
        let settleDuration = 0.105
        let attackEnd = anticipationDuration + attackDuration
        let reboundEnd = attackEnd + reboundDuration
        let settleEnd = reboundEnd + settleDuration

        switch elapsed {
        case ..<anticipationDuration:
            return Sample(contactProgress: 0, isComplete: false)
        case ..<attackEnd:
            let progress = Float((elapsed - anticipationDuration) / attackDuration)
            return Sample(contactProgress: smoothstep(progress), isComplete: false)
        case ..<reboundEnd:
            let progress = Float((elapsed - attackEnd) / reboundDuration)
            return Sample(contactProgress: 1 - smoothstep(progress) * 0.12, isComplete: false)
        case ..<settleEnd:
            let progress = Float((elapsed - reboundEnd) / settleDuration)
            return Sample(contactProgress: 0.88 + smoothstep(progress) * 0.12, isComplete: false)
        default:
            return Sample(contactProgress: 1, isComplete: true)
        }
    }

    private func smoothstep(_ value: Float) -> Float {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
