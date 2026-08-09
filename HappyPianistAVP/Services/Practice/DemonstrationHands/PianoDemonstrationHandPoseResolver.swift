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

struct PianoDemonstrationHandPoseResolution: Equatable {
    struct Unreachable: Equatable {
        let occurrenceID: String
        let contactErrorMeters: Float
    }

    let pose: PianoDemonstrationHandPose?
    let reachableOccurrenceIDs: Set<String>
    let unreachableOccurrences: [Unreachable]

    static let empty = PianoDemonstrationHandPoseResolution(
        pose: nil,
        reachableOccurrenceIDs: [],
        unreachableOccurrences: []
    )
}

struct PianoDemonstrationHandPoseResolver {
    static let maximumContactErrorMeters: Float = 0.005

    func resolve(
        hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget],
        strikeProgressByOccurrenceID: [String: Float] = [:]
    ) -> PianoDemonstrationHandPoseResolution {
        let handTargets = targets.filter { $0.hand == hand }
        guard handTargets.isEmpty == false else {
            return .empty
        }

        var targetByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget] = [:]
        var unreachableOccurrences: [PianoDemonstrationHandPoseResolution.Unreachable] = []
        for target in handTargets {
            guard Self.isFinite(target.contactPositionLocal) else {
                unreachableOccurrences.append(unreachable(for: target, error: .infinity))
                continue
            }
            guard targetByFinger[target.finger] == nil else {
                unreachableOccurrences.append(unreachable(for: target, error: .infinity))
                continue
            }
            targetByFinger[target.finger] = target
        }
        while targetByFinger.isEmpty == false {
            guard let pose = makePose(
                hand: hand,
                targetsByFinger: targetByFinger,
                strikeProgressByOccurrenceID: strikeProgressByOccurrenceID
            ) else {
                unreachableOccurrences += targetByFinger.values.map {
                    unreachable(for: $0, error: .infinity)
                }
                targetByFinger.removeAll()
                break
            }
            let failures = reachabilityFailures(
                in: pose,
                targetsByFinger: targetByFinger,
                strikeProgressByOccurrenceID: strikeProgressByOccurrenceID
            )
            guard failures.isEmpty == false else {
                return PianoDemonstrationHandPoseResolution(
                    pose: pose,
                    reachableOccurrenceIDs: Set(targetByFinger.values.map(\.occurrenceID)),
                    unreachableOccurrences: sorted(unreachableOccurrences)
                )
            }
            unreachableOccurrences += failures
            let failedOccurrenceIDs = Set(failures.map(\.occurrenceID))
            targetByFinger = targetByFinger.filter {
                failedOccurrenceIDs.contains($0.value.occurrenceID) == false
            }
        }

        return PianoDemonstrationHandPoseResolution(
            pose: nil,
            reachableOccurrenceIDs: [],
            unreachableOccurrences: sorted(unreachableOccurrences)
        )
    }

    private func makePose(
        hand: PianoDemonstrationHand,
        targetsByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget],
        strikeProgressByOccurrenceID: [String: Float]
    ) -> PianoDemonstrationHandPose? {
        let palmCenter = makePalmCenter(
            hand: hand,
            targetsByFinger: targetsByFinger,
            strikeProgressByOccurrenceID: strikeProgressByOccurrenceID
        )
        let fingers = PianoDemonstrationFinger.allCases.map { finger in
            makeFingerPose(
                finger: finger,
                hand: hand,
                palmCenter: palmCenter,
                target: targetsByFinger[finger],
                strikeProgress: targetsByFinger[finger].map {
                    strikeProgressByOccurrenceID[$0.occurrenceID] ?? 1
                } ?? 1
            )
        }
        guard Self.isFinite(palmCenter)
        else {
            return nil
        }

        return PianoDemonstrationHandPose(
            hand: hand,
            palmCenterLocal: palmCenter,
            fingers: fingers
        )
    }

    private func reachabilityFailures(
        in pose: PianoDemonstrationHandPose,
        targetsByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget],
        strikeProgressByOccurrenceID: [String: Float]
    ) -> [PianoDemonstrationHandPoseResolution.Unreachable] {
        targetsByFinger.compactMap { finger, target in
            guard let actualTip = pose.fingerPose(for: finger)?.jointPositionsLocal.last else {
                return unreachable(for: target, error: .infinity)
            }
            let expectedTip = desiredTip(
                for: target,
                strikeProgress: strikeProgressByOccurrenceID[target.occurrenceID] ?? 1
            )
            let error = simd_distance(actualTip, expectedTip)
            guard error.isFinite, error > Self.maximumContactErrorMeters else {
                return nil
            }
            return unreachable(for: target, error: error)
        }
    }

    private func unreachable(
        for target: PianoDemonstrationHandTarget,
        error: Float
    ) -> PianoDemonstrationHandPoseResolution.Unreachable {
        PianoDemonstrationHandPoseResolution.Unreachable(
            occurrenceID: target.occurrenceID,
            contactErrorMeters: error
        )
    }

    private func sorted(
        _ occurrences: [PianoDemonstrationHandPoseResolution.Unreachable]
    ) -> [PianoDemonstrationHandPoseResolution.Unreachable] {
        occurrences.sorted { $0.occurrenceID < $1.occurrenceID }
    }

    private func makePalmCenter(
        hand: PianoDemonstrationHand,
        targetsByFinger: [PianoDemonstrationFinger: PianoDemonstrationHandTarget],
        strikeProgressByOccurrenceID: [String: Float]
    ) -> SIMD3<Float> {
        let palmX = targetsByFinger.reduce(into: Float.zero) { partial, item in
            partial += item.value.contactPositionLocal.x - fingerOffsetX(item.key, hand: hand)
        } / Float(targetsByFinger.count)
        let averageZ = targetsByFinger.values.reduce(into: Float.zero) { partial, target in
            partial += target.contactPositionLocal.z
        } / Float(targetsByFinger.count)
        let surfaceY = targetsByFinger.values.map(\.contactPositionLocal.y).max() ?? 0
        let palmStrikeProgress = targetsByFinger.values
            .filter { $0.phase == .triggered }
            .map { min(1, max(0, strikeProgressByOccurrenceID[$0.occurrenceID] ?? 1)) }
            .min() ?? 1

        return SIMD3<Float>(
            palmX,
            surfaceY + 0.045 + (1 - palmStrikeProgress) * 0.012,
            averageZ + 0.050 + (1 - palmStrikeProgress) * 0.004
        )
    }

    private func makeFingerPose(
        finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand,
        palmCenter: SIMD3<Float>,
        target: PianoDemonstrationHandTarget?,
        strikeProgress: Float
    ) -> PianoDemonstrationFingerPose {
        let knuckle = palmCenter + fingerRootOffset(finger, hand: hand)
        let tip = target.map {
            desiredTip(for: $0, strikeProgress: strikeProgress)
        } ?? naturalTip(finger: finger, hand: hand, palmCenter: palmCenter)
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

    private func desiredTip(
        for target: PianoDemonstrationHandTarget,
        strikeProgress: Float
    ) -> SIMD3<Float> {
        let clampedStrikeProgress = min(1, max(0, strikeProgress))
        let velocity = Float(target.velocity) / 127
        let strikeLift = target.phase == .triggered
            ? (1 - clampedStrikeProgress) * (0.018 + velocity * 0.008)
            : 0
        return target.contactPositionLocal + SIMD3<Float>(0, strikeLift, 0)
    }

    private func naturalTip(
        finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand,
        palmCenter: SIMD3<Float>
    ) -> SIMD3<Float> {
        let rightHandOffset: SIMD3<Float> = switch finger {
        case .thumb: [-0.053, -0.014, -0.058]
        case .index: [-0.017, -0.016, -0.101]
        case .middle: [0, -0.018, -0.115]
        case .ring: [0.019, -0.018, -0.104]
        case .little: [0.038, -0.015, -0.082]
        }
        return palmCenter + mirrored(rightHandOffset, for: hand)
    }

    private func fingerRootOffset(
        _ finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand
    ) -> SIMD3<Float> {
        // ponytail: these are the authored MCP locations in the packaged Blender rig.
        let rightHandOffset: SIMD3<Float> = switch finger {
        case .thumb: [-0.030, -0.004, -0.004]
        case .index: [-0.016, 0, -0.027]
        case .middle: [0, 0.001, -0.031]
        case .ring: [0.017, 0, -0.028]
        case .little: [0.033, -0.001, -0.022]
        }
        return mirrored(rightHandOffset, for: hand)
    }

    private func mirrored(
        _ rightHandOffset: SIMD3<Float>,
        for hand: PianoDemonstrationHand
    ) -> SIMD3<Float> {
        hand == .right
            ? rightHandOffset
            : SIMD3<Float>(-rightHandOffset.x, rightHandOffset.y, rightHandOffset.z)
    }

    private func fingerOffsetX(
        _ finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand
    ) -> Float {
        fingerRootOffset(finger, hand: hand).x
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
        let solvedTip = root + direction * min(initialDistance, totalLength * 0.99)

        let vertical = SIMD3<Float>(0, 1, 0)
        let archDirection = normalized(
            vertical - direction * simd_dot(vertical, direction),
            fallback: [0, 0, 1]
        )
        var joints = [
            root,
            root + direction * segmentLengths[0] + archDirection * archHeight,
            root + direction * (segmentLengths[0] + segmentLengths[1]) + archDirection * archHeight * 0.72,
            solvedTip,
        ]

        // ponytail: a tiny fixed FABRIK budget is deterministic; add joint limits only if authored poses need them.
        for _ in 0 ..< 24 {
            joints[3] = solvedTip
            for index in stride(from: 2, through: 0, by: -1) {
                let towardParent = normalized(joints[index] - joints[index + 1], fallback: -direction)
                joints[index] = joints[index + 1] + towardParent * segmentLengths[index]
            }
            joints[0] = root
            for index in 0 ..< 3 {
                let towardChild = normalized(joints[index + 1] - joints[index], fallback: direction)
                joints[index + 1] = joints[index] + towardChild * segmentLengths[index]
            }
            if simd_distance(joints[3], solvedTip) < 0.000_05 { break }
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
