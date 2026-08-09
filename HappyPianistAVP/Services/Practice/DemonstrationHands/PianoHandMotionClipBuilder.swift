import Foundation
import MusicXML
import Practice
import simd

/// Builds immutable hand-motion candidates from the current planning snapshot.
///
/// This builder deliberately has no RealityKit dependency so its work can stay outside
/// `RealityView.update` and the main actor.
struct PianoHandMotionClipBuilder: Sendable {
    private static let maximumThumbFlexionRadians: Float = 1.05
    private static let maximumFingerFlexionRadians: Float = 1.35
    private static let maximumThumbAbductionRadians: Float = 0.50
    private static let maximumFingerAbductionRadians: Float = 0.35
    private static let maximumJointAngularVelocityRadiansPerSecond: Float = 8
    private static let maximumWristVelocityMetersPerSecond: Float = 0.6
    private static let maximumWristAngularVelocityRadiansPerSecond: Float = 3
    struct KeyboardLayout: Equatable, Sendable {
        struct Key: Equatable, Sendable {
            let midiNote: Int
            let contactPositionLocal: SIMD3<Float>
        }

        let keys: [Key]
        let duplicateMIDINotes: Set<Int>

        init(keys: [Key]) {
            self.keys = keys.sorted { $0.midiNote < $1.midiNote }
            duplicateMIDINotes = Set(
                Dictionary(grouping: keys, by: \.midiNote)
                    .compactMap { $0.value.count > 1 ? $0.key : nil }
            )
        }
    }

    struct Input: Equatable, Sendable {
        let contacts: PianoKeyContactTimeline
        let fingeringPlan: PianoFingeringPlanner.Plan
        let keyboardLayout: KeyboardLayout
        let scoreRevision: String

        init(
            contacts: PianoKeyContactTimeline,
            fingeringPlan: PianoFingeringPlanner.Plan,
            keyboardLayout: KeyboardLayout,
            scoreRevision: String
        ) {
            self.contacts = contacts
            self.fingeringPlan = fingeringPlan
            self.keyboardLayout = keyboardLayout
            self.scoreRevision = scoreRevision
        }
    }

    struct Result: Equatable, Sendable {
        let clips: [PianoHandMotionClip]
        let rejectedOccurrenceIDs: [String]
    }

    func build(input: Input) throws -> Result {
        try Task.checkCancellation()
        let keyByMIDINote = Dictionary(
            input.keyboardLayout.keys.map { ($0.midiNote, $0.contactPositionLocal) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolutionByOccurrenceID = Dictionary(
            input.fingeringPlan.results.map { ($0.occurrenceID, $0.resolution) },
            uniquingKeysWith: { first, _ in first }
        )
        var plannedContacts: [PlannedContact] = []
        var rejectedOccurrenceIDs: [String] = []

        for contact in input.contacts.contacts {
            try Task.checkCancellation()
            guard case let .planned(hand, finger, _) = resolutionByOccurrenceID[contact.occurrenceID],
                  hand == .left || hand == .right,
                  let onsetSeconds = contact.onsetSeconds,
                  let releaseSeconds = contact.releaseSeconds,
                  onsetSeconds.isFinite,
                  releaseSeconds.isFinite,
                  releaseSeconds >= onsetSeconds,
                  input.keyboardLayout.duplicateMIDINotes.contains(contact.midiNote) == false,
                  let contactPositionLocal = keyByMIDINote[contact.midiNote],
                  Self.isFinite(contactPositionLocal)
            else {
                rejectedOccurrenceIDs.append(contact.occurrenceID)
                continue
            }
            plannedContacts.append(PlannedContact(
                occurrenceID: contact.occurrenceID,
                hand: hand,
                finger: finger,
                onsetSeconds: onsetSeconds,
                releaseSeconds: releaseSeconds,
                contactPositionLocal: contactPositionLocal
            ))
        }

        let metadata = PianoHandMotionClip.Metadata(
            generatorRevision: "p2-t5",
            skeletonRevision: "piano-demonstration-21-joint-v1",
            scoreRevision: input.scoreRevision
        )
        var clips: [PianoHandMotionClip] = []
        for hand in [ScoreHand.left, .right] {
            try Task.checkCancellation()
            let contacts = plannedContacts.filter { $0.hand == hand }
            guard contacts.isEmpty == false else { continue }
            do {
                clips.append(try makeClip(metadata: metadata, hand: hand, contacts: contacts))
            } catch is MotionConstraintError {
                // A clip is atomic per hand: never publish a partial pose sequence whose
                // coverage claims motions it cannot safely produce.
                rejectedOccurrenceIDs += contacts.map(\.occurrenceID)
            }
        }
        return Result(
            clips: clips,
            rejectedOccurrenceIDs: Array(Set(rejectedOccurrenceIDs)).sorted()
        )
    }

    func buildOffMain(input: Input) async throws -> Result {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) { [self, input] in
            try build(input: input)
        }
        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    private func makeClip(
        metadata: PianoHandMotionClip.Metadata,
        hand: ScoreHand,
        contacts: [PlannedContact]
    ) throws -> PianoHandMotionClip {
        let contactsByOnset = Dictionary(grouping: contacts, by: \.onsetSeconds)
        var previousJointAngles = Array(
            repeating: SIMD2<Float>.zero,
            count: PianoHandMotionClip.jointCount
        )
        var previousRootTransform: PianoHandMotionClip.RootTransform?
        var previousOnset: TimeInterval?
        var frames: [PianoHandMotionClip.Frame] = []

        for onsetSeconds in contactsByOnset.keys.sorted() {
            try Task.checkCancellation()
            let contactsAtOnset = contactsByOnset[onsetSeconds] ?? []
            guard let targetJointAngles = Self.targetJointAngles(
                for: contactsAtOnset,
                palmCenter: Self.palmCenter(for: contactsAtOnset),
                hand: hand
            ),
            let targetRootTransform = PianoDemonstrationHandRootPlanner.rootTransform(
                for: hand,
                targets: contactsAtOnset.map {
                    .init(finger: $0.finger, contactPositionLocal: $0.contactPositionLocal)
                }
            )
            else {
                throw MotionConstraintError()
            }
            let availableSeconds = previousOnset.map { max(0, Float(onsetSeconds - $0)) } ?? .infinity
            let maximumDelta = availableSeconds * Self.maximumJointAngularVelocityRadiansPerSecond
            guard zip(previousJointAngles, targetJointAngles).allSatisfy({ previous, target in
                Self.isWithinAngularVelocityLimit(
                    from: previous,
                    to: target,
                    maximumDelta: maximumDelta
                )
            }) else {
                throw MotionConstraintError()
            }

            if let previousRootTransform, let previousOnset {
                let transitionSeconds = Self.requiredWristTransitionSeconds(
                    from: previousRootTransform,
                    to: targetRootTransform
                )
                guard transitionSeconds <= availableSeconds else {
                    throw MotionConstraintError()
                }
                let transitionStartSeconds = onsetSeconds - TimeInterval(transitionSeconds)
                if transitionStartSeconds > previousOnset {
                    frames.append(PianoHandMotionClip.Frame(
                        timeSeconds: transitionStartSeconds,
                        rootTransform: previousRootTransform,
                        jointRotations: previousJointAngles.map { Self.jointRotation(for: $0) }
                    ))
                }
            }

            previousJointAngles = targetJointAngles
            previousRootTransform = targetRootTransform
            previousOnset = onsetSeconds
            frames.append(PianoHandMotionClip.Frame(
                timeSeconds: onsetSeconds,
                rootTransform: targetRootTransform,
                jointRotations: targetJointAngles.map { Self.jointRotation(for: $0) }
            ))
        }
        return try PianoHandMotionClip(
            metadata: metadata,
            hand: hand,
            frames: frames,
            coverage: contacts.map {
                .init(
                    occurrenceID: $0.occurrenceID,
                    finger: $0.finger,
                    onsetSeconds: $0.onsetSeconds,
                    releaseSeconds: $0.releaseSeconds
                )
            }
        )
    }

    private static func isFinite(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func palmCenter(for contacts: [PlannedContact]) -> SIMD3<Float> {
        contacts.reduce(into: SIMD3<Float>.zero) { position, contact in
            position += contact.contactPositionLocal
        } / Float(contacts.count)
    }

    private static func targetJointAngles(
        for contacts: [PlannedContact],
        palmCenter: SIMD3<Float>,
        hand: ScoreHand
    ) -> [SIMD2<Float>]? {
        guard Set(contacts.map(\.finger)).count == contacts.count else { return nil }
        var jointAngles = Array(
            repeating: SIMD2<Float>.zero,
            count: PianoHandMotionClip.jointCount
        )
        for contact in contacts {
            let startIndex = 1 + (contact.finger - 1) * 4
            guard (1 ... 5).contains(contact.finger),
                  jointAngles.indices.contains(startIndex + 3)
            else {
                return nil
            }

            let isThumb = contact.finger == 1
            let lateralOffset = contact.contactPositionLocal.x - palmCenter.x
            let flexion = (isThumb ? 0.25 : 0.35) + abs(lateralOffset) * 6
            let abduction = lateralOffset * (hand == .right ? 3 : -3)
            let maximumFlexion = isThumb
                ? Self.maximumThumbFlexionRadians
                : Self.maximumFingerFlexionRadians
            let maximumAbduction = isThumb
                ? Self.maximumThumbAbductionRadians
                : Self.maximumFingerAbductionRadians
            guard flexion <= maximumFlexion,
                  abs(abduction) <= maximumAbduction
            else {
                return nil
            }

            let flexionWeights: [Float] = isThumb
                ? [0.32, 0.42, 0.20, 0.06]
                : [0.18, 0.42, 0.28, 0.12]
            for (offset, weight) in flexionWeights.enumerated() {
                jointAngles[startIndex + offset] = SIMD2(
                    flexion * weight,
                    offset == 0 ? abduction : 0
                )
            }
        }
        return jointAngles
    }

    private static func isWithinAngularVelocityLimit(
        from previous: SIMD2<Float>,
        to target: SIMD2<Float>,
        maximumDelta: Float
    ) -> Bool {
        abs(target.x - previous.x) <= maximumDelta
            && abs(target.y - previous.y) <= maximumDelta
    }

    private static func jointRotation(for angles: SIMD2<Float>) -> SIMD4<Float> {
        let flexion = simd_quatf(angle: angles.x, axis: SIMD3<Float>(1, 0, 0))
        let abduction = simd_quatf(angle: angles.y, axis: SIMD3<Float>(0, 0, 1))
        return (abduction * flexion).vector
    }

    private static func requiredWristTransitionSeconds(
        from previous: PianoHandMotionClip.RootTransform,
        to target: PianoHandMotionClip.RootTransform
    ) -> Float {
        let translationSeconds = simd_distance(previous.translation, target.translation)
            / Self.maximumWristVelocityMetersPerSecond
        let rotationSeconds = Self.rotationDistanceRadians(from: previous.rotation, to: target.rotation)
            / Self.maximumWristAngularVelocityRadiansPerSecond
        return max(translationSeconds, rotationSeconds)
    }

    private static func rotationDistanceRadians(
        from previous: SIMD4<Float>,
        to target: SIMD4<Float>
    ) -> Float {
        let previousRotation = simd_quatf(vector: previous)
        let targetRotation = simd_quatf(vector: target)
        return 2 * acos(min(1, abs(simd_dot(previousRotation.vector, targetRotation.vector))))
    }
}

private extension PianoHandMotionClipBuilder {
    struct MotionConstraintError: Error {}

    struct PlannedContact: Sendable {
        let occurrenceID: String
        let hand: ScoreHand
        let finger: Int
        let onsetSeconds: TimeInterval
        let releaseSeconds: TimeInterval
        let contactPositionLocal: SIMD3<Float>
    }
}

/// Pure keyboard-local root planning shared by the clip builder and the temporary P1 pose path.
///
/// It owns the authored MCP offsets and wrist clearance so the two paths cannot diverge before
/// T8 removes the old direct pose player.
struct PianoDemonstrationHandRootPlanner {
    struct Target: Sendable {
        let finger: Int
        let contactPositionLocal: SIMD3<Float>
    }

    private static let wristHeightMeters: Float = 0.045
    private static let wristDepthMeters: Float = 0.050
    private static let preparedWristLiftMeters: Float = 0.012
    private static let preparedWristDepthMeters: Float = 0.004

    static func rootTransform(
        for hand: ScoreHand,
        targets: [Target],
        strikeProgress: Float = 1
    ) -> PianoHandMotionClip.RootTransform? {
        guard (hand == .left || hand == .right),
              targets.isEmpty == false,
              targets.allSatisfy({
                  (1 ... 5).contains($0.finger) && isFinite($0.contactPositionLocal)
              })
        else {
            return nil
        }

        let rotation = rootRotation(for: hand, targets: targets)
        let rootRotation = simd_quatf(vector: rotation)
        let palmX = targets.reduce(into: Float.zero) { partial, target in
            partial += target.contactPositionLocal.x
                - rootRotation.act(fingerRootOffset(target.finger, hand: hand)).x
        } / Float(targets.count)
        let surfaceY = targets.map(\.contactPositionLocal.y).max() ?? 0
        let averageZ = targets.reduce(into: Float.zero) { partial, target in
            partial += target.contactPositionLocal.z
        } / Float(targets.count)
        let progress = min(1, max(0, strikeProgress.isFinite ? strikeProgress : 1))
        let translation = SIMD3<Float>(
            palmX,
            surfaceY + Self.wristHeightMeters + (1 - progress) * Self.preparedWristLiftMeters,
            averageZ + Self.wristDepthMeters + (1 - progress) * Self.preparedWristDepthMeters
        )
        guard isFinite(translation) else { return nil }
        return .init(translation: translation, rotation: rotation)
    }

    static func rootTransform(
        for hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget],
        strikeProgressByOccurrenceID: [String: Float] = [:]
    ) -> PianoHandMotionClip.RootTransform? {
        let progress = targets
            .filter { $0.phase == .triggered }
            .map { strikeProgressByOccurrenceID[$0.occurrenceID] ?? 1 }
            .min() ?? 1
        return rootTransform(
            for: hand == .left ? .left : .right,
            targets: targets.map {
                .init(finger: $0.finger.rawValue, contactPositionLocal: $0.contactPositionLocal)
            },
            strikeProgress: progress
        )
    }

    static func fingerRootOffset(
        _ finger: PianoDemonstrationFinger,
        hand: PianoDemonstrationHand
    ) -> SIMD3<Float> {
        fingerRootOffset(finger.rawValue, hand: hand == .left ? .left : .right)
    }

    private static func rootRotation(
        for hand: ScoreHand,
        targets: [Target]
    ) -> SIMD4<Float> {
        let horizontalSpan = (targets.map(\.contactPositionLocal.x).max() ?? 0)
            - (targets.map(\.contactPositionLocal.x).min() ?? 0)
        let side: Float = hand == .right ? -1 : 1
        let yaw = side * min(0.08, 0.02 + horizontalSpan * 0.2)
        return simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)).vector
    }

    private static func fingerRootOffset(_ finger: Int, hand: ScoreHand) -> SIMD3<Float> {
        let rightHandOffset: SIMD3<Float> = switch finger {
        case 1: [-0.030, -0.004, -0.004]
        case 2: [-0.016, 0, -0.027]
        case 3: [0, 0.001, -0.031]
        case 4: [0.017, 0, -0.028]
        case 5: [0.033, -0.001, -0.022]
        default: .zero
        }
        return hand == .right
            ? rightHandOffset
            : SIMD3<Float>(-rightHandOffset.x, rightHandOffset.y, rightHandOffset.z)
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
