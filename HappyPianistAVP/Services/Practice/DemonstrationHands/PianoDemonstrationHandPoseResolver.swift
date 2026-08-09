import Foundation
import MusicXML
import Practice
import simd

struct PianoDemonstrationFingerPose: Equatable {
    let finger: PianoDemonstrationFinger
    let jointPositionsLocal: [SIMD3<Float>]
}

struct PianoDemonstrationHandPose: Equatable {
    let hand: PianoDemonstrationHand
    let rootTransform: PianoHandMotionClip.RootTransform
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
        guard let rootTransform = PianoDemonstrationHandRootPlanner.rootTransform(
            for: hand,
            targets: Array(targetsByFinger.values),
            strikeProgressByOccurrenceID: strikeProgressByOccurrenceID
        ) else {
            return nil
        }
        let fingers = PianoDemonstrationFinger.allCases.map { finger in
            makeFingerPose(
                finger: finger,
                hand: hand,
                rootTransform: rootTransform,
                target: targetsByFinger[finger],
                strikeProgress: targetsByFinger[finger].map {
                    strikeProgressByOccurrenceID[$0.occurrenceID] ?? 1
                } ?? 1
            )
        }
        return PianoDemonstrationHandPose(
            hand: hand,
            rootTransform: rootTransform,
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

    private func makeFingerPose(
        finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand,
        rootTransform: PianoHandMotionClip.RootTransform,
        target: PianoDemonstrationHandTarget?,
        strikeProgress: Float
    ) -> PianoDemonstrationFingerPose {
        let tip = target.map {
            desiredTip(for: $0, strikeProgress: strikeProgress)
        } ?? PianoDemonstrationHandRootPlanner.naturalTip(
            finger: finger.rawValue,
            hand: hand == .left ? .left : .right,
            rootTransform: rootTransform
        )
        guard let joints = PianoDemonstrationHandRootPlanner.fingerJointPositions(
            finger: finger.rawValue,
            hand: hand == .left ? .left : .right,
            rootTransform: rootTransform,
            tip: tip,
        ) else {
            return PianoDemonstrationFingerPose(finger: finger, jointPositionsLocal: [])
        }

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

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
