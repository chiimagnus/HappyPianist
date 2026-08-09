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
    private static let maximumContactErrorMeters: Float = 0.005
    private static let maximumKeyPenetrationMeters: Float = 0.003
    private static let maximumRootCollisionCorrectionMeters: Float = 0.010
    private static let collisionClearanceMeters: Float = 0.0005
    private static let fingerCapsuleRadiusMeters: Float = 0.0025
    private static let palmCapsuleRadiusMeters: Float = 0.014
    private static let tipContactAllowanceMeters: Float = 0.006
    private static let initialPreparationDuration: TimeInterval = 0.20
    private static let transitionValidationInterval: TimeInterval = 1.0 / 120.0
    struct KeyboardLayout: Equatable, Sendable {
        struct Key: Equatable, Sendable {
            let midiNote: Int
            let contactPositionLocal: SIMD3<Float>
            let surfaceLocalY: Float
            let topSurfaceSizeLocal: SIMD2<Float>
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
            input.keyboardLayout.keys.map { ($0.midiNote, $0) },
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
                  let key = keyByMIDINote[contact.midiNote],
                  Self.isValid(key)
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
                key: key
            ))
        }

        let metadata = PianoHandMotionClip.Metadata(
            generatorRevision: "p2-t7",
            skeletonRevision: "piano-demonstration-21-joint-v1",
            scoreRevision: input.scoreRevision
        )
        var clips: [PianoHandMotionClip] = []
        for hand in [ScoreHand.left, .right] {
            try Task.checkCancellation()
            let contacts = plannedContacts.filter { $0.hand == hand }
            guard contacts.isEmpty == false else { continue }
            do {
                clips.append(try makeClip(
                    metadata: metadata,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: input.keyboardLayout.keys
                ))
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
        contacts: [PlannedContact],
        keyboardKeys: [KeyboardLayout.Key]
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
            let contactsAtOnset = Self.activeContacts(in: contacts, at: onsetSeconds)
            guard let initialJointAngles = Self.targetJointAngles(
                for: contactsAtOnset,
                palmCenter: Self.palmCenter(for: contactsAtOnset),
                hand: hand
            ),
            let solvedPose = Self.solvePose(
                hand: hand,
                contacts: contactsAtOnset,
                initialJointAngles: initialJointAngles
            )
            else {
                throw MotionConstraintError()
            }
            let targetJointRotations = solvedPose.jointAngles.map(Self.jointRotation)
            guard let targetRootTransform = Self.minimumCollisionFreeRootTransform(
                solvedPose.rootTransform,
                hand: hand,
                jointRotations: targetJointRotations,
                keyboardKeys: keyboardKeys
            ), Self.satisfiesKinematicConstraints(
                hand: hand,
                contacts: contactsAtOnset,
                rootTransform: targetRootTransform,
                jointRotations: targetJointRotations,
                keyboardKeys: keyboardKeys
            ) else {
                throw MotionConstraintError()
            }
            let targetFrame = PianoHandMotionClip.Frame(
                timeSeconds: onsetSeconds,
                rootTransform: targetRootTransform,
                jointRotations: targetJointRotations
            )

            if previousOnset == nil {
                let preparationFrame = PianoHandMotionClip.Frame(
                    timeSeconds: onsetSeconds - Self.initialPreparationDuration,
                    rootTransform: .init(
                        translation: targetRootTransform.translation + SIMD3<Float>(0, 0.035, 0),
                        rotation: targetRootTransform.rotation
                    ),
                    jointRotations: Array(
                        repeating: SIMD4<Float>(0, 0, 0, 1),
                        count: PianoHandMotionClip.jointCount
                    )
                )
                guard Self.satisfiesKinematicConstraints(
                    hand: hand,
                    contacts: [],
                    rootTransform: preparationFrame.rootTransform,
                    jointRotations: preparationFrame.jointRotations,
                    keyboardKeys: keyboardKeys
                ), Self.validatesTransition(
                    from: preparationFrame,
                    to: targetFrame,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: keyboardKeys
                ) else {
                    throw MotionConstraintError()
                }
                frames.append(preparationFrame)
            }

            let transitionStartFloor = previousOnset.map { previousOnset in
                contacts.lazy.filter {
                    $0.onsetSeconds <= previousOnset
                        && $0.releaseSeconds > previousOnset
                        && $0.releaseSeconds < onsetSeconds
                }
                .map(\.releaseSeconds)
                .max() ?? previousOnset
            }
            let availableSeconds = transitionStartFloor.map {
                max(0, Float(onsetSeconds - $0))
            } ?? .infinity
            let maximumDelta = availableSeconds * Self.maximumJointAngularVelocityRadiansPerSecond
            guard zip(previousJointAngles, solvedPose.jointAngles).allSatisfy({ previous, target in
                Self.isWithinAngularVelocityLimit(
                    from: previous,
                    to: target,
                    maximumDelta: maximumDelta
                )
            }) else {
                throw MotionConstraintError()
            }

            if let previousRootTransform, let previousOnset, let transitionStartFloor {
                let transitionSeconds = Self.requiredWristTransitionSeconds(
                    from: previousRootTransform,
                    to: targetRootTransform
                )
                guard transitionSeconds <= availableSeconds else {
                    throw MotionConstraintError()
                }
                let transitionStartSeconds = max(
                    transitionStartFloor,
                    onsetSeconds - TimeInterval(transitionSeconds)
                )
                if transitionStartSeconds > previousOnset {
                    frames.append(PianoHandMotionClip.Frame(
                        timeSeconds: transitionStartSeconds,
                        rootTransform: previousRootTransform,
                        jointRotations: previousJointAngles.map { Self.jointRotation(for: $0) }
                    ))
                }
                guard let transitionFrame = frames.last,
                      Self.validatesTransition(
                          from: transitionFrame,
                          to: targetFrame,
                          hand: hand,
                          contacts: contacts,
                          keyboardKeys: keyboardKeys
                      )
                else {
                    throw MotionConstraintError()
                }
            }

            previousJointAngles = solvedPose.jointAngles
            previousRootTransform = targetRootTransform
            previousOnset = onsetSeconds
            frames.append(targetFrame)
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

    private static func isFinite(_ vector: SIMD2<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite
    }

    private static func isValid(_ key: KeyboardLayout.Key) -> Bool {
        isFinite(key.contactPositionLocal)
            && key.surfaceLocalY.isFinite
            && isFinite(key.topSurfaceSizeLocal)
            && key.topSurfaceSizeLocal.x > 0
            && key.topSurfaceSizeLocal.y > 0
    }

    private static func activeContacts(
        in contacts: [PlannedContact],
        at timeSeconds: TimeInterval
    ) -> [PlannedContact] {
        contacts.filter {
            $0.onsetSeconds <= timeSeconds && timeSeconds <= $0.releaseSeconds
        }
    }

    private static func validatesTransition(
        from lower: PianoHandMotionClip.Frame,
        to upper: PianoHandMotionClip.Frame,
        hand: ScoreHand,
        contacts: [PlannedContact],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Bool {
        let duration = upper.timeSeconds - lower.timeSeconds
        guard duration >= 0 else { return false }
        let samples = max(1, Int((duration / Self.transitionValidationInterval).rounded(.up)))
        for index in 1 ..< samples {
            let progress = Float(index) / Float(samples)
            let timeSeconds = lower.timeSeconds + duration * TimeInterval(progress)
            let frame = PianoHandMotionClip.Frame(
                timeSeconds: timeSeconds,
                rootTransform: .init(
                    translation: simd_mix(
                        lower.rootTransform.translation,
                        upper.rootTransform.translation,
                        SIMD3(repeating: progress)
                    ),
                    rotation: simd_slerp(
                        simd_quatf(vector: lower.rootTransform.rotation),
                        simd_quatf(vector: upper.rootTransform.rotation),
                        progress
                    ).vector
                ),
                jointRotations: zip(lower.jointRotations, upper.jointRotations).map { lower, upper in
                    simd_slerp(
                        simd_quatf(vector: lower),
                        simd_quatf(vector: upper),
                        progress
                    ).vector
                }
            )
            guard Self.satisfiesKinematicConstraints(
                hand: hand,
                contacts: Self.activeContacts(in: contacts, at: timeSeconds),
                rootTransform: frame.rootTransform,
                jointRotations: frame.jointRotations,
                keyboardKeys: keyboardKeys
            ) else {
                return false
            }
        }
        return true
    }

    private static func isValidRotation(_ rotation: SIMD4<Float>) -> Bool {
        guard rotation.x.isFinite,
              rotation.y.isFinite,
              rotation.z.isFinite,
              rotation.w.isFinite
        else {
            return false
        }
        return abs(simd_length_squared(rotation) - 1) <= 0.001
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

    /// Solves the authored skeleton, rather than an idealized proxy chain, before a frame can be published.
    private static func solvePose(
        hand: ScoreHand,
        contacts: [PlannedContact],
        initialJointAngles: [SIMD2<Float>]
    ) -> SolvedPose? {
        let targets = contacts.map {
            PianoDemonstrationHandRootPlanner.Target(
                finger: $0.finger,
                contactPositionLocal: $0.contactPositionLocal
            )
        }
        guard var rootTransform = PianoDemonstrationHandRootPlanner.rootTransform(
            for: hand,
            targets: targets
        ), initialJointAngles.count == PianoHandMotionClip.jointCount
        else {
            return nil
        }
        var jointAngles = initialJointAngles

        // ponytail: fixed coordinate descent is deterministic for this 21-joint hand; replace it
        // with a general IK solver only when the authored rig gains coupled or extra joints.
        for step: Float in [0.32, 0.16, 0.08, 0.04, 0.02, 0.01] {
            for _ in 0 ..< 8 {
                guard let alignedRootTransform = PianoDemonstrationHandRootPlanner.alignedRootTransform(
                    rootTransform,
                    hand: hand,
                    targets: targets,
                    jointRotations: jointAngles.map(Self.jointRotation)
                ) else {
                    return nil
                }
                rootTransform = alignedRootTransform

                for contact in contacts {
                    let startIndex = 1 + (contact.finger - 1) * 4
                    for jointIndex in startIndex ..< startIndex + 3 {
                        for component in 0 ... 1 {
                            let original = jointAngles[jointIndex][component]
                            var bestValue = original
                            var bestError = Self.contactErrorSquared(
                                for: contact,
                                hand: hand,
                                rootTransform: rootTransform,
                                jointAngles: jointAngles
                            )
                            for candidate in [original - step, original + step] {
                                let constrained = Self.constrainedJointAngle(
                                    candidate,
                                    component: component,
                                    finger: contact.finger
                                )
                                jointAngles[jointIndex][component] = constrained
                                let error = Self.contactErrorSquared(
                                    for: contact,
                                    hand: hand,
                                    rootTransform: rootTransform,
                                    jointAngles: jointAngles
                                )
                                if error < bestError {
                                    bestError = error
                                    bestValue = constrained
                                }
                            }
                            jointAngles[jointIndex][component] = bestValue
                        }
                    }
                }
            }
        }

        guard let alignedRootTransform = PianoDemonstrationHandRootPlanner.alignedRootTransform(
            rootTransform,
            hand: hand,
            targets: targets,
            jointRotations: jointAngles.map(Self.jointRotation)
        ), contacts.allSatisfy({
            Self.contactErrorSquared(
                for: $0,
                hand: hand,
                rootTransform: alignedRootTransform,
                jointAngles: jointAngles
            ) <= pow(Self.maximumContactErrorMeters, 2)
        })
        else {
            return nil
        }
        return SolvedPose(rootTransform: alignedRootTransform, jointAngles: jointAngles)
    }

    private static func constrainedJointAngle(
        _ value: Float,
        component: Int,
        finger: Int
    ) -> Float {
        if component == 0 {
            let maximum = finger == 1
                ? Self.maximumThumbFlexionRadians
                : Self.maximumFingerFlexionRadians
            return min(max(value, 0), maximum)
        }
        let maximum = finger == 1
            ? Self.maximumThumbAbductionRadians
            : Self.maximumFingerAbductionRadians
        return min(max(value, -maximum), maximum)
    }

    private static func contactErrorSquared(
        for contact: PlannedContact,
        hand: ScoreHand,
        rootTransform: PianoHandMotionClip.RootTransform,
        jointAngles: [SIMD2<Float>]
    ) -> Float {
        guard let tip = PianoDemonstrationHandSkeleton.fingerJointPositions(
            finger: contact.finger,
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointAngles.map(Self.jointRotation)
        )?.last
        else {
            return .infinity
        }
        return simd_distance_squared(tip, contact.contactPositionLocal)
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

    private static func minimumCollisionFreeRootTransform(
        _ rootTransform: PianoHandMotionClip.RootTransform,
        hand: ScoreHand,
        jointRotations: [SIMD4<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> PianoHandMotionClip.RootTransform? {
        guard let positions = PianoDemonstrationHandSkeleton.jointPositions(
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        ), positions.indices.contains(17) else {
            return nil
        }
        let thumb = positions[1]
        let little = positions[17]
        let palm = Capsule(start: thumb, end: little, radius: Self.palmCapsuleRadiusMeters)
        let requiredLift = keyboardKeys.reduce(into: Float.zero) { lift, key in
            guard palm.overlapsHorizontally(key) else { return }
            lift = max(
                lift,
                key.surfaceLocalY + palm.radius + Self.collisionClearanceMeters
                    - min(palm.start.y, palm.end.y)
            )
        }
        guard requiredLift <= Self.maximumRootCollisionCorrectionMeters else { return nil }

        let correctedTranslation = rootTransform.translation + SIMD3(
            0,
            max(0, requiredLift),
            0
        )
        guard isFinite(correctedTranslation) else { return nil }
        return .init(translation: correctedTranslation, rotation: rootTransform.rotation)
    }

    private static func satisfiesKinematicConstraints(
        hand: ScoreHand,
        contacts: [PlannedContact],
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Bool {
        guard jointRotations.count == PianoHandMotionClip.jointCount,
              jointRotations.allSatisfy(Self.isValidRotation),
              keyboardKeys.allSatisfy(Self.isValid),
              Set(contacts.map(\.finger)).count == contacts.count
        else {
            return false
        }
        guard let positions = PianoDemonstrationHandSkeleton.jointPositions(
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        ) else {
            return false
        }

        let contactsByFinger = Dictionary(
            uniqueKeysWithValues: contacts.map { ($0.finger, $0) }
        )
        let fingers = (1 ... 5).compactMap { finger -> FingerGeometry? in
            let start = 1 + (finger - 1) * 4
            guard positions.indices.contains(start + 3) else { return nil }
            let joints = Array(positions[start ... start + 3])
            guard Self.hasValidBoneLengths(joints, finger: finger, hand: hand)
            else {
                return nil
            }
            if let contact = contactsByFinger[finger], Self.isValidTipContact(contact, tip: joints[3]) == false {
                return nil
            }
            return FingerGeometry(
                finger: finger,
                joints: joints,
                targetKey: contactsByFinger[finger]?.key
            )
        }
        guard fingers.count == 5 else { return false }

        let fingerCapsules = fingers.flatMap { finger in
            zip(finger.joints, finger.joints.dropFirst()).enumerated().map { segmentIndex, segment in
                FingerCapsule(
                    finger: finger.finger,
                    segmentIndex: segmentIndex,
                    capsule: Capsule(
                        start: segment.0,
                        end: segment.1,
                        radius: Self.fingerCapsuleRadiusMeters
                    ),
                    targetKey: finger.targetKey,
                    allowsTipContact: finger.targetKey != nil && segment.1 == finger.joints.last
                )
            }
        }

        let palm = Capsule(
            start: positions[1],
            end: positions[17],
            radius: Self.palmCapsuleRadiusMeters
        )
        guard Self.hasNoFingerSelfIntersections(fingerCapsules, palm: palm) else { return false }
        return Self.hasNoKeyboardIntersections(
            fingerCapsules: fingerCapsules,
            palm: palm,
            keyboardKeys: keyboardKeys
        )
    }

    private static func hasValidBoneLengths(
        _ joints: [SIMD3<Float>],
        finger: Int,
        hand: ScoreHand
    ) -> Bool {
        guard let segmentLengths = PianoDemonstrationHandSkeleton.fingerSegmentLengths(finger, hand: hand),
              joints.count == segmentLengths.count + 1
        else {
            return false
        }
        return zip(zip(joints, joints.dropFirst()), segmentLengths).allSatisfy { segment, length in
            abs(simd_distance(segment.0, segment.1) - length) < 0.000_05
        }
    }

    private static func isValidTipContact(_ contact: PlannedContact, tip: SIMD3<Float>) -> Bool {
        let key = contact.key
        let halfSize = key.topSurfaceSizeLocal / 2
        let lateralOffset = SIMD2(
            abs(tip.x - key.contactPositionLocal.x),
            abs(tip.z - key.contactPositionLocal.z)
        )
        let verticalOffset = tip.y - key.surfaceLocalY
        return lateralOffset.x <= halfSize.x
            && lateralOffset.y <= halfSize.y
            && verticalOffset <= Self.maximumContactErrorMeters
            && verticalOffset >= -Self.maximumKeyPenetrationMeters
            && simd_distance(tip, contact.contactPositionLocal) <= Self.maximumContactErrorMeters
    }

    private static func hasNoFingerSelfIntersections(
        _ capsules: [FingerCapsule],
        palm: Capsule
    ) -> Bool {
        for leftIndex in capsules.indices {
            for rightIndex in capsules.indices.dropFirst(leftIndex + 1)
                where capsules[leftIndex].finger != capsules[rightIndex].finger
            {
                let left = capsules[leftIndex].capsule
                let right = capsules[rightIndex].capsule
                if Self.segmentDistanceSquared(
                    from: left.start,
                    to: left.end,
                    and: right.start,
                    to: right.end
                ) < pow(left.radius + right.radius, 2) {
                    return false
                }
            }
        }
        for finger in capsules where finger.segmentIndex > 0 {
            if Self.segmentDistanceSquared(
                from: finger.capsule.start,
                to: finger.capsule.end,
                and: palm.start,
                to: palm.end
            ) < pow(finger.capsule.radius + palm.radius, 2) {
                return false
            }
        }
        return true
    }

    private static func hasNoKeyboardIntersections(
        fingerCapsules: [FingerCapsule],
        palm: Capsule,
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Bool {
        for key in keyboardKeys where palm.intersectsKeyboard(key) {
            return false
        }
        for finger in fingerCapsules {
            for key in keyboardKeys {
                let capsule = finger.allowsTipContact && finger.targetKey?.midiNote == key.midiNote
                    ? finger.capsule.shortened(by: Self.tipContactAllowanceMeters)
                    : finger.capsule
                if capsule.intersectsKeyboard(key) {
                    return false
                }
            }
        }
        return true
    }

    private static func segmentDistanceSquared(
        from startA: SIMD3<Float>,
        to endA: SIMD3<Float>,
        and startB: SIMD3<Float>,
        to endB: SIMD3<Float>
    ) -> Float {
        let directionA = endA - startA
        let directionB = endB - startB
        let betweenStarts = startA - startB
        let a = simd_dot(directionA, directionA)
        let b = simd_dot(directionA, directionB)
        let c = simd_dot(directionA, betweenStarts)
        let e = simd_dot(directionB, directionB)
        let f = simd_dot(directionB, betweenStarts)
        let denominator = a * e - b * b
        var parameterA: Float = denominator > 0.000_000_1
            ? min(1, max(0, (b * f - c * e) / denominator))
            : 0
        var parameterB = (b * parameterA + f) / max(e, 0.000_000_1)
        if parameterB < 0 {
            parameterB = 0
            parameterA = min(1, max(0, -c / max(a, 0.000_000_1)))
        } else if parameterB > 1 {
            parameterB = 1
            parameterA = min(1, max(0, (b - c) / max(a, 0.000_000_1)))
        }
        let difference = betweenStarts + directionA * parameterA - directionB * parameterB
        return simd_dot(difference, difference)
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
        let key: KeyboardLayout.Key

        var contactPositionLocal: SIMD3<Float> {
            key.contactPositionLocal
        }
    }

    struct SolvedPose {
        let rootTransform: PianoHandMotionClip.RootTransform
        let jointAngles: [SIMD2<Float>]
    }

    struct FingerGeometry {
        let finger: Int
        let joints: [SIMD3<Float>]
        let targetKey: KeyboardLayout.Key?
    }

    struct FingerCapsule {
        let finger: Int
        let segmentIndex: Int
        let capsule: Capsule
        let targetKey: KeyboardLayout.Key?
        let allowsTipContact: Bool
    }

    struct Capsule {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let radius: Float

        func shortened(by distance: Float) -> Self {
            let direction = end - start
            let length = simd_length(direction)
            guard length > distance, distance > 0 else { return self }
            return Self(start: start, end: end - direction / length * distance, radius: radius)
        }

        func overlapsHorizontally(_ key: KeyboardLayout.Key) -> Bool {
            let halfSize = key.topSurfaceSizeLocal / 2 + SIMD2(repeating: radius)
            let minimum = SIMD2(min(start.x, end.x), min(start.z, end.z))
            let maximum = SIMD2(max(start.x, end.x), max(start.z, end.z))
            let keyMinimum = SIMD2(key.contactPositionLocal.x, key.contactPositionLocal.z) - halfSize
            let keyMaximum = SIMD2(key.contactPositionLocal.x, key.contactPositionLocal.z) + halfSize
            return minimum.x <= keyMaximum.x
                && maximum.x >= keyMinimum.x
                && minimum.y <= keyMaximum.y
                && maximum.y >= keyMinimum.y
        }

        func intersectsKeyboard(_ key: KeyboardLayout.Key) -> Bool {
            let halfSize = key.topSurfaceSizeLocal / 2 + SIMD2(repeating: radius)
            let minimum = SIMD3(
                key.contactPositionLocal.x - halfSize.x,
                -Float.greatestFiniteMagnitude,
                key.contactPositionLocal.z - halfSize.y
            )
            let maximum = SIMD3(
                key.contactPositionLocal.x + halfSize.x,
                key.surfaceLocalY + radius,
                key.contactPositionLocal.z + halfSize.y
            )
            return intersectsAABB(minimum: minimum, maximum: maximum)
        }

        private func intersectsAABB(minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> Bool {
            let direction = end - start
            var startParameter: Float = 0
            var endParameter: Float = 1
            for axis in 0 ..< 3 {
                let origin = start[axis]
                let delta = direction[axis]
                if abs(delta) < 0.000_000_1 {
                    guard minimum[axis] <= origin, origin <= maximum[axis] else { return false }
                    continue
                }
                let inverse = 1 / delta
                var entry = (minimum[axis] - origin) * inverse
                var exit = (maximum[axis] - origin) * inverse
                if entry > exit {
                    swap(&entry, &exit)
                }
                startParameter = max(startParameter, entry)
                endParameter = min(endParameter, exit)
                guard startParameter <= endParameter else { return false }
            }
            return true
        }
    }
}

/// Pure keyboard-local hand geometry used by clip planning and collision validation.
struct PianoDemonstrationHandRootPlanner {
    struct Target: Sendable {
        let finger: Int
        let contactPositionLocal: SIMD3<Float>
    }

    static func rootTransform(
        for hand: ScoreHand,
        targets: [Target]
    ) -> PianoHandMotionClip.RootTransform? {
        guard (hand == .left || hand == .right),
              targets.isEmpty == false,
              Set(targets.map(\.finger)).count == targets.count,
              targets.allSatisfy({
                  (1 ... 5).contains($0.finger) && isFinite($0.contactPositionLocal)
              })
        else {
            return nil
        }

        let rotation = rootRotation(for: hand, targets: targets)
        let restRotations = Array(
            repeating: SIMD4<Float>(0, 0, 0, 1),
            count: PianoHandMotionClip.jointCount
        )
        return alignedRootTransform(
            .init(translation: .zero, rotation: rotation),
            hand: hand,
            targets: targets,
            jointRotations: restRotations
        )
    }

    static func alignedRootTransform(
        _ rootTransform: PianoHandMotionClip.RootTransform,
        hand: ScoreHand,
        targets: [Target],
        jointRotations: [SIMD4<Float>]
    ) -> PianoHandMotionClip.RootTransform? {
        guard let positions = PianoDemonstrationHandSkeleton.jointPositions(
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        ), targets.allSatisfy({
            (1 ... 5).contains($0.finger) && isFinite($0.contactPositionLocal)
        })
        else {
            return nil
        }
        let translationCorrection = targets.reduce(into: SIMD3<Float>.zero) { correction, target in
            correction += target.contactPositionLocal - positions[1 + (target.finger - 1) * 4 + 3]
        } / Float(targets.count)
        let translation = rootTransform.translation + translationCorrection
        guard isFinite(translation) else { return nil }
        return .init(translation: translation, rotation: rootTransform.rotation)
    }

    static func fingerJointPositions(
        finger: Int,
        hand: ScoreHand,
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>]
    ) -> [SIMD3<Float>]? {
        PianoDemonstrationHandSkeleton.fingerJointPositions(
            finger: finger,
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        )
    }

    private static func rootRotation(
        for hand: ScoreHand,
        targets: [Target]
    ) -> SIMD4<Float> {
        let horizontalSpan = (targets.map(\.contactPositionLocal.x).max() ?? 0)
            - (targets.map(\.contactPositionLocal.x).min() ?? 0)
        let side: Float = hand == .right ? -1 : 1
        let yaw = side * min(0.08, 0.02 + horizontalSpan * 0.2)
        let keyboardFacingRotation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        return (keyboardFacingRotation * yawRotation).vector
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
