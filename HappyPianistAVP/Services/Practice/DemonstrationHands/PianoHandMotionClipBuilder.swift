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
    private static let maximumThumbExtensionRadians: Float = 0.35
    private static let maximumFingerExtensionRadians: Float = 0.25
    private static let maximumThumbAbductionRadians: Float = 0.50
    private static let maximumFingerAbductionRadians: Float = 0.35
    private static let maximumJointAngularVelocityRadiansPerSecond: Float = 8
    private static let maximumWristVelocityMetersPerSecond: Float = 0.6
    private static let maximumWristAngularVelocityRadiansPerSecond: Float = 3
    private static let maximumContactErrorMeters: Float = 0.005
    private static let maximumKeyPenetrationMeters: Float = 0.003
    private static let collisionClearanceMeters: Float = 0.0005
    private static let fingerCapsuleRadiusMeters: Float = 0.0025
    private static let palmCapsuleRadiusMeters: Float = 0.014
    private static let initialPreparationDuration: TimeInterval = 0.20
    private static let transitionValidationInterval: TimeInterval = 1.0 / 120.0
    struct KeyboardLayout: Equatable, Sendable {
        struct Key: Equatable, Sendable {
            let midiNote: Int
            let contactPositionLocal: SIMD3<Float>
            let surfaceLocalY: Float
            let topSurfaceCenterLocal: SIMD2<Float>
            let topSurfaceSizeLocal: SIMD2<Float>

            init(
                midiNote: Int,
                contactPositionLocal: SIMD3<Float>,
                surfaceLocalY: Float,
                topSurfaceCenterLocal: SIMD2<Float>? = nil,
                topSurfaceSizeLocal: SIMD2<Float>
            ) {
                self.midiNote = midiNote
                self.contactPositionLocal = contactPositionLocal
                self.surfaceLocalY = surfaceLocalY
                self.topSurfaceCenterLocal = topSurfaceCenterLocal
                    ?? SIMD2(contactPositionLocal.x, contactPositionLocal.z)
                self.topSurfaceSizeLocal = topSurfaceSizeLocal
            }
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

        init(keyboardGeometry: PianoKeyboardGeometry) {
            let blackKeys = keyboardGeometry.keys.filter { $0.kind == .black }
            self.init(keys: keyboardGeometry.keys.map { key in
                let interiorSign: Float = key.localCenter.z >= 0 ? 1 : -1
                let frontEdgeZ = key.localCenter.z - interiorSign * key.localSize.z / 2
                let contactZ: Float
                switch key.kind {
                case .white:
                    let keyMinX = key.localCenter.x - key.localSize.x / 2
                    let keyMaxX = key.localCenter.x + key.localSize.x / 2
                    let clearDepth = blackKeys.compactMap { blackKey -> Float? in
                        let blackMinX = blackKey.localCenter.x - blackKey.localSize.x / 2
                        let blackMaxX = blackKey.localCenter.x + blackKey.localSize.x / 2
                        guard keyMinX < blackMaxX, keyMaxX > blackMinX else { return nil }
                        let blackFrontEdgeZ = blackKey.localCenter.z
                            - interiorSign * blackKey.localSize.z / 2
                        let depth = (blackFrontEdgeZ - frontEdgeZ) * interiorSign
                        return depth > 0 ? depth : nil
                    }.min() ?? key.localSize.z / 2
                    contactZ = frontEdgeZ + interiorSign * clearDepth * 0.375
                case .black:
                    contactZ = frontEdgeZ + interiorSign * key.localSize.z * 0.35
                }
                return .init(
                    midiNote: key.midiNote,
                    contactPositionLocal: SIMD3<Float>(
                        key.localCenter.x,
                        key.surfaceLocalY,
                        contactZ
                    ),
                    surfaceLocalY: key.surfaceLocalY,
                    topSurfaceCenterLocal: SIMD2(key.localCenter.x, key.localCenter.z),
                    topSurfaceSizeLocal: SIMD2(key.localSize.x, key.localSize.z)
                )
            })
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
            skeletonRevision: "piano-demonstration-21-joint-v2",
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
        var previousJointAngles = Self.neutralJointAngles()
        var previousRootTransform: PianoHandMotionClip.RootTransform?
        var previousOnset: TimeInterval?
        var frames: [PianoHandMotionClip.Frame] = []

        for onsetSeconds in contactsByOnset.keys.sorted() {
            try Task.checkCancellation()
            let contactsAtOnset = Self.activeContacts(in: contacts, at: onsetSeconds)
            let activeFingers = Set(contactsAtOnset.map(\.finger))
            let boundaryReleaseContacts = contacts.filter {
                $0.onsetSeconds < onsetSeconds
                    && abs($0.releaseSeconds - onsetSeconds) <= 0.000_000_001
                    && activeFingers.contains($0.finger) == false
            }
            let poseContactsAtOnset = contactsAtOnset + boundaryReleaseContacts
            guard let suggestedJointAngles = Self.targetJointAngles(
                for: contactsAtOnset,
                palmCenter: Self.palmCenter(for: contactsAtOnset),
                hand: hand
            ) else {
                throw MotionConstraintError()
            }
            let initialJointAngles: [SIMD2<Float>]
            if let previousOnset {
                let previousActiveContacts = Self.activeContacts(in: contacts, at: previousOnset)
                var continuedAngles = suggestedJointAngles
                for contact in previousActiveContacts {
                    let finger = contact.finger
                    let startIndex = 1 + (finger - 1) * 4
                    let remainsHeld = contact.releaseSeconds > onsetSeconds
                    if remainsHeld {
                        for jointIndex in startIndex ..< startIndex + 4 {
                            continuedAngles[jointIndex] = previousJointAngles[jointIndex]
                        }
                        continue
                    }

                    let recoverySeconds = max(0, Float(onsetSeconds - contact.releaseSeconds))
                    let maximumRecoveryRadians = recoverySeconds
                        * Self.maximumJointAngularVelocityRadiansPerSecond
                    for jointIndex in startIndex ..< startIndex + 4 {
                        let previousAngle = previousJointAngles[jointIndex]
                        let suggestedAngle = suggestedJointAngles[jointIndex]
                        continuedAngles[jointIndex] = Self.jointAngle(
                            from: previousAngle,
                            toward: suggestedAngle,
                            maximumRotationRadians: maximumRecoveryRadians
                        )
                    }
                }
                initialJointAngles = continuedAngles
            } else {
                initialJointAngles = suggestedJointAngles
            }
            guard let solvedPose = Self.solvePose(
                hand: hand,
                contacts: poseContactsAtOnset,
                initialJointAngles: initialJointAngles,
                preferredRootTransform: boundaryReleaseContacts.isEmpty ? previousRootTransform : nil,
                keyboardKeys: keyboardKeys
            ) else {
                throw MotionConstraintError()
            }
            let targetJointRotations = solvedPose.jointAngles.map(Self.jointRotation)
            let targetRootTransform = solvedPose.rootTransform
            guard Self.satisfiesKinematicConstraints(
                hand: hand,
                requiredContacts: contactsAtOnset,
                tipContactAllowances: poseContactsAtOnset,
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
                let preparationJointRotations = Self.neutralJointAngles().map(Self.jointRotation)
                let liftedPreparationRoot = PianoHandMotionClip.RootTransform(
                    translation: targetRootTransform.translation + SIMD3<Float>(0, 0.035, 0),
                    rotation: targetRootTransform.rotation
                )
                guard let preparationRoot = Self.minimumClearanceRootTransform(
                    liftedPreparationRoot,
                    hand: hand,
                    jointRotations: preparationJointRotations,
                    keyboardKeys: keyboardKeys
                ) else {
                    throw MotionConstraintError()
                }
                let preparationFrame = PianoHandMotionClip.Frame(
                    timeSeconds: onsetSeconds - Self.initialPreparationDuration,
                    rootTransform: preparationRoot,
                    jointRotations: preparationJointRotations
                )
                guard Self.requiredWristTransitionSeconds(
                    from: preparationFrame.rootTransform,
                    to: targetFrame.rootTransform
                ) <= Float(Self.initialPreparationDuration),
                Self.satisfiesKinematicConstraints(
                    hand: hand,
                    requiredContacts: [],
                    tipContactAllowances: [],
                    rootTransform: preparationFrame.rootTransform,
                    jointRotations: preparationFrame.jointRotations,
                    keyboardKeys: keyboardKeys
                ) else {
                    throw MotionConstraintError()
                }

                frames.append(preparationFrame)
                if Self.validatesTransition(
                    from: preparationFrame,
                    to: targetFrame,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: keyboardKeys
                ) == false {
                    let neutralAngles = Self.neutralJointAngles()
                    if let intermediateFrames = Self.collisionAvoidanceIntermediateFrames(
                        from: preparationFrame,
                        to: targetFrame,
                        lowerJointAngles: neutralAngles,
                        upperJointAngles: solvedPose.jointAngles,
                        hand: hand,
                        contacts: contacts,
                        adjustableFingers: Set(1 ... 5),
                        keyboardKeys: keyboardKeys
                    ) {
                        frames.append(contentsOf: intermediateFrames)
                    } else if let arcFrames = Self.clearanceArcFrames(
                        from: preparationFrame,
                        to: targetFrame,
                        earliestStartSeconds: preparationFrame.timeSeconds,
                        hand: hand,
                        contacts: contacts,
                        keyboardKeys: keyboardKeys
                    ) {
                        frames.append(contentsOf: arcFrames)
                    } else {
                        throw MotionConstraintError()
                    }
                }
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
            if let previousRootTransform, let previousOnset, let transitionStartFloor {
                let previousFrame = PianoHandMotionClip.Frame(
                    timeSeconds: previousOnset,
                    rootTransform: previousRootTransform,
                    jointRotations: previousJointAngles.map { Self.jointRotation(for: $0) }
                )
                guard let transitionFrames = Self.transitionFrames(
                    from: previousFrame,
                    to: targetFrame,
                    earliestStartSeconds: transitionStartFloor,
                    hand: hand,
                    contacts: contacts,
                    previousJointAngles: previousJointAngles,
                    targetJointAngles: solvedPose.jointAngles,
                    keyboardKeys: keyboardKeys
                ) else {
                    throw MotionConstraintError()
                }
                frames.append(contentsOf: transitionFrames)
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
        let halfSize = key.topSurfaceSizeLocal / 2
        let contactOffset = SIMD2(
            abs(key.contactPositionLocal.x - key.topSurfaceCenterLocal.x),
            abs(key.contactPositionLocal.z - key.topSurfaceCenterLocal.y)
        )
        let verticalOffset = key.contactPositionLocal.y - key.surfaceLocalY
        return isFinite(key.contactPositionLocal)
            && key.surfaceLocalY.isFinite
            && isFinite(key.topSurfaceCenterLocal)
            && isFinite(key.topSurfaceSizeLocal)
            && key.topSurfaceSizeLocal.x > 0
            && key.topSurfaceSizeLocal.y > 0
            && contactOffset.x <= halfSize.x
            && contactOffset.y <= halfSize.y
            && verticalOffset <= Self.maximumContactErrorMeters
            && verticalOffset >= -Self.maximumKeyPenetrationMeters
    }

    private static func activeContacts(
        in contacts: [PlannedContact],
        at timeSeconds: TimeInterval
    ) -> [PlannedContact] {
        contacts.filter {
            $0.onsetSeconds <= timeSeconds && timeSeconds < $0.releaseSeconds
        }
    }

    private static func validatesTransition(
        from lower: PianoHandMotionClip.Frame,
        to upper: PianoHandMotionClip.Frame,
        hand: ScoreHand,
        contacts: [PlannedContact],
        allowanceStartSeconds: TimeInterval? = nil,
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Bool {
        let duration = upper.timeSeconds - lower.timeSeconds
        guard duration >= 0 else { return false }
        let allowanceWindowStart = allowanceStartSeconds ?? lower.timeSeconds
        let allowanceCandidates = contacts.filter {
            $0.onsetSeconds <= upper.timeSeconds && $0.releaseSeconds >= allowanceWindowStart
        }
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
            let requiredContacts = Self.activeContacts(in: contacts, at: timeSeconds)
            let tipContactAllowances = Dictionary(grouping: allowanceCandidates, by: \.finger)
                .compactMap { _, candidates -> PlannedContact? in
                    candidates.min { lhs, rhs in
                        func distance(to contact: PlannedContact) -> TimeInterval {
                            if timeSeconds < contact.onsetSeconds {
                                return contact.onsetSeconds - timeSeconds
                            }
                            if timeSeconds > contact.releaseSeconds {
                                return timeSeconds - contact.releaseSeconds
                            }
                            return 0
                        }
                        return distance(to: lhs) < distance(to: rhs)
                    }
                }
            guard Self.satisfiesKinematicConstraints(
                hand: hand,
                requiredContacts: requiredContacts,
                tipContactAllowances: tipContactAllowances,
                rootTransform: frame.rootTransform,
                jointRotations: frame.jointRotations,
                keyboardKeys: keyboardKeys
            ) else {
                return false
            }
        }
        return true
    }

    private static func transitionFrames(
        from previous: PianoHandMotionClip.Frame,
        to target: PianoHandMotionClip.Frame,
        earliestStartSeconds: TimeInterval,
        hand: ScoreHand,
        contacts: [PlannedContact],
        previousJointAngles: [SIMD2<Float>],
        targetJointAngles: [SIMD2<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> [PianoHandMotionClip.Frame]? {
        let availableSeconds = Float(target.timeSeconds - earliestStartSeconds)
        guard availableSeconds >= 0,
              let jointTransitionSeconds = requiredJointTransitionSeconds(
                  from: previous.jointRotations,
                  to: target.jointRotations
              )
        else {
            return nil
        }

        let directSeconds = max(
            requiredWristTransitionSeconds(
                from: previous.rootTransform,
                to: target.rootTransform
            ),
            jointTransitionSeconds
        )
        if directSeconds <= availableSeconds {
            let directStartSeconds = target.timeSeconds - TimeInterval(directSeconds)
            let directStart = PianoHandMotionClip.Frame(
                timeSeconds: directStartSeconds,
                rootTransform: previous.rootTransform,
                jointRotations: previous.jointRotations
            )
            if validatesTransition(
                from: directStart,
                to: target,
                hand: hand,
                contacts: contacts,
                allowanceStartSeconds: earliestStartSeconds,
                keyboardKeys: keyboardKeys
            ) {
                return directStartSeconds > previous.timeSeconds ? [directStart] : []
            }
        }

        let priorContacts = contacts.filter {
            $0.onsetSeconds <= previous.timeSeconds && $0.releaseSeconds > previous.timeSeconds
        }
        let releasingBeforeTarget = priorContacts
            .filter { $0.releaseSeconds < target.timeSeconds }
            .map(\.releaseSeconds)
            .max()
        let transitionDuration = target.timeSeconds - previous.timeSeconds
        if let releasingBeforeTarget,
           releasingBeforeTarget > previous.timeSeconds,
           releasingBeforeTarget < target.timeSeconds
        {
            for preparationProgress: TimeInterval in [1.0, 0.9, 0.8, 0.7] {
                let prepositionSeconds = previous.timeSeconds
                    + (releasingBeforeTarget - previous.timeSeconds) * preparationProgress
                let prepositionContacts = priorContacts.filter {
                $0.releaseSeconds >= prepositionSeconds
            }
            let heldFingers = Set(prepositionContacts.map(\.finger))
            let targetFingers = Set(Self.activeContacts(in: contacts, at: target.timeSeconds).map(\.finger))
            let idleFingers = Set(1 ... 5).subtracting(heldFingers).subtracting(targetFingers)
            let adjustablePrepositionFingers = heldFingers.union(idleFingers)
            let firstAvailable = max(0, Float(prepositionSeconds - previous.timeSeconds))
            let secondAvailable = max(0, Float(target.timeSeconds - prepositionSeconds))
            let fullWristSeconds = requiredWristTransitionSeconds(
                from: previous.rootTransform,
                to: target.rootTransform
            )
            let minimumRootProgress = fullWristSeconds > secondAvailable && fullWristSeconds > 0
                ? 1 - secondAvailable / fullWristSeconds
                : 0
            let maximumRootProgress = fullWristSeconds > 0
                ? min(1, firstAvailable / fullWristSeconds)
                : 0
            let minimumJointProgress = jointTransitionSeconds > secondAvailable && jointTransitionSeconds > 0
                ? 1 - secondAvailable / jointTransitionSeconds
                : 0
            let maximumJointProgress = jointTransitionSeconds > 0
                ? min(1, firstAvailable / jointTransitionSeconds)
                : 0
            let progressOffsets: [Float] = [1 / 64, 1 / 32, 1 / 16, 1 / 8]

            for offset in progressOffsets {
                let rootProgress = minimumRootProgress > 0
                    ? min(maximumRootProgress, minimumRootProgress + offset)
                    : 0
                let jointProgress = minimumJointProgress > 0
                    ? min(maximumJointProgress, minimumJointProgress + offset)
                    : 0
                guard rootProgress >= minimumRootProgress,
                      jointProgress >= minimumJointProgress
                else {
                    continue
                }

                let candidateRoot = PianoHandMotionClip.RootTransform(
                    translation: simd_mix(
                        previous.rootTransform.translation,
                        target.rootTransform.translation,
                        SIMD3(repeating: rootProgress)
                    ),
                    rotation: simd_slerp(
                        simd_quatf(vector: previous.rootTransform.rotation),
                        simd_quatf(vector: target.rootTransform.rotation),
                        rootProgress
                    ).vector
                )
                var initialPrepositionAngles = previousJointAngles
                if jointProgress > 0.000_001 {
                    for index in initialPrepositionAngles.indices where index > 0 {
                        let finger = ((index - 1) / 4) + 1
                        guard heldFingers.contains(finger) == false else { continue }
                        initialPrepositionAngles[index] = simd_mix(
                            previousJointAngles[index],
                            targetJointAngles[index],
                            SIMD2<Float>(repeating: jointProgress)
                        )
                    }
                }
                let prepositionTargets = prepositionContacts.map {
                    PianoDemonstrationHandRootPlanner.Target(
                        finger: $0.finger,
                        contactPositionLocal: $0.contactPositionLocal
                    )
                }
                let transitionBounds = JointTransitionBounds(
                    previousJointAngles: previousJointAngles,
                    targetJointAngles: targetJointAngles,
                    maximumFromPreviousRadians: firstAvailable
                        * Self.maximumJointAngularVelocityRadiansPerSecond,
                    maximumToTargetRadians: secondAvailable
                        * Self.maximumJointAngularVelocityRadiansPerSecond
                )
                guard let prepositionPose = optimizePose(
                    hand: hand,
                    contacts: prepositionContacts,
                    targets: prepositionTargets,
                    initialJointAngles: initialPrepositionAngles,
                    initialRootTransform: candidateRoot,
                    preserveRootHeight: true,
                    preserveRootTranslation: true,
                    adjustableFingers: adjustablePrepositionFingers,
                    jointTransitionBounds: transitionBounds,
                    keyboardKeys: keyboardKeys
                ) else {
                    continue
                }
                let prepositionFrame = PianoHandMotionClip.Frame(
                    timeSeconds: prepositionSeconds,
                    rootTransform: prepositionPose.rootTransform,
                    jointRotations: prepositionPose.jointAngles.map(Self.jointRotation)
                )
                let firstRequired = max(
                    requiredWristTransitionSeconds(
                        from: previous.rootTransform,
                        to: prepositionFrame.rootTransform
                    ),
                    requiredJointTransitionSeconds(
                        from: previous.jointRotations,
                        to: prepositionFrame.jointRotations
                    ) ?? .infinity
                )
                let prepositionConstraintsOK = satisfiesKinematicConstraints(
                    hand: hand,
                    requiredContacts: prepositionContacts,
                    tipContactAllowances: prepositionContacts,
                    rootTransform: prepositionFrame.rootTransform,
                    jointRotations: prepositionFrame.jointRotations,
                    keyboardKeys: keyboardKeys
                )
                let directPrepositionTransitionOK = firstRequired <= firstAvailable && validatesTransition(
                    from: previous,
                    to: prepositionFrame,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: keyboardKeys
                )
                let approachFrames: [PianoHandMotionClip.Frame]
                if directPrepositionTransitionOK {
                    approachFrames = [prepositionFrame]
                } else if firstRequired <= firstAvailable,
                          prepositionConstraintsOK,
                          let intermediateFrames = collisionAvoidanceIntermediateFrames(
                              from: previous,
                              to: prepositionFrame,
                              lowerJointAngles: previousJointAngles,
                              upperJointAngles: prepositionPose.jointAngles,
                              hand: hand,
                              contacts: contacts,
                              adjustableFingers: adjustablePrepositionFingers,
                              keyboardKeys: keyboardKeys
                          )
                {
                    approachFrames = intermediateFrames + [prepositionFrame]
                } else {
                    continue
                }

                let secondRequired = max(
                    requiredWristTransitionSeconds(
                        from: prepositionFrame.rootTransform,
                        to: target.rootTransform
                    ),
                    requiredJointTransitionSeconds(
                        from: prepositionFrame.jointRotations,
                        to: target.jointRotations
                    ) ?? .infinity
                )
                let secondTransitionOK = secondRequired <= secondAvailable && validatesTransition(
                    from: prepositionFrame,
                    to: target,
                    hand: hand,
                    contacts: contacts,
                    allowanceStartSeconds: prepositionSeconds,
                    keyboardKeys: keyboardKeys
                )
                if secondTransitionOK {
                    return approachFrames
                }

                if secondRequired <= secondAvailable,
                   let releaseIntermediateFrames = collisionAvoidanceIntermediateFrames(
                       from: prepositionFrame,
                       to: target,
                       lowerJointAngles: prepositionPose.jointAngles,
                       upperJointAngles: targetJointAngles,
                       hand: hand,
                       contacts: contacts,
                       adjustableFingers: Set(1 ... 5),
                       keyboardKeys: keyboardKeys
                   )
                {
                    return approachFrames + releaseIntermediateFrames
                }
                if let releaseRoute = clearanceArcFrames(
                    from: prepositionFrame,
                    to: target,
                    earliestStartSeconds: prepositionSeconds,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: keyboardKeys
                ) {
                    return approachFrames + releaseRoute
                }
            }
            }
        } else {
            for progress: Float in [0.5, 0.6, 0.7, 0.8] {
                let prepositionSeconds = previous.timeSeconds + transitionDuration * TimeInterval(progress)
                let prepositionContacts = activeContacts(in: contacts, at: prepositionSeconds)
                guard prepositionContacts.isEmpty == false else { continue }
                let candidateRoot = PianoHandMotionClip.RootTransform(
                    translation: simd_mix(
                        previous.rootTransform.translation,
                        target.rootTransform.translation,
                        SIMD3(repeating: progress)
                    ),
                    rotation: simd_slerp(
                        simd_quatf(vector: previous.rootTransform.rotation),
                        simd_quatf(vector: target.rootTransform.rotation),
                        progress
                    ).vector
                )
                let prepositionTargets = prepositionContacts.map {
                    PianoDemonstrationHandRootPlanner.Target(
                        finger: $0.finger,
                        contactPositionLocal: $0.contactPositionLocal
                    )
                }
                guard let prepositionPose = optimizePose(
                    hand: hand,
                    contacts: prepositionContacts,
                    targets: prepositionTargets,
                    initialJointAngles: previousJointAngles,
                    initialRootTransform: candidateRoot,
                    preserveRootHeight: true,
                    preserveRootTranslation: true,
                    adjustableFingers: Set(prepositionContacts.map(\.finger)),
                    keyboardKeys: keyboardKeys
                ) else {
                    continue
                }
                let firstAvailable = Float(prepositionSeconds - previous.timeSeconds)
                let secondAvailable = Float(target.timeSeconds - prepositionSeconds)
                let maximumJointDelta = firstAvailable * Self.maximumJointAngularVelocityRadiansPerSecond
                let heldFingers = Set(prepositionContacts.map(\.finger))
                let targetFingers = Set(Self.activeContacts(in: contacts, at: target.timeSeconds).map(\.finger))
                var prepositionAngles = prepositionPose.jointAngles
                for finger in 1 ... 5 where heldFingers.contains(finger) == false {
                    let isIncomingFinger = targetFingers.contains(finger)
                    let startIndex = 1 + (finger - 1) * 4
                    for jointIndex in startIndex ..< startIndex + 4 {
                        let previousAngle = previousJointAngles[jointIndex]
                        let targetAngle = targetJointAngles[jointIndex]
                        let desiredAngle = SIMD2<Float>(
                            isIncomingFinger ? 0 : targetAngle.x,
                            targetAngle.y
                        )
                        prepositionAngles[jointIndex] = SIMD2<Float>(
                            previousAngle.x + min(
                                maximumJointDelta,
                                max(-maximumJointDelta, desiredAngle.x - previousAngle.x)
                            ),
                            previousAngle.y + min(
                                maximumJointDelta,
                                max(-maximumJointDelta, desiredAngle.y - previousAngle.y)
                            )
                        )
                    }
                }
                let prepositionFrame = PianoHandMotionClip.Frame(
                    timeSeconds: prepositionSeconds,
                    rootTransform: prepositionPose.rootTransform,
                    jointRotations: prepositionAngles.map(Self.jointRotation)
                )
                let firstRequired = max(
                    requiredWristTransitionSeconds(
                        from: previous.rootTransform,
                        to: prepositionFrame.rootTransform
                    ),
                    requiredJointTransitionSeconds(
                        from: previous.jointRotations,
                        to: prepositionFrame.jointRotations
                    ) ?? .infinity
                )
                let secondRequired = max(
                    requiredWristTransitionSeconds(
                        from: prepositionFrame.rootTransform,
                        to: target.rootTransform
                    ),
                    requiredJointTransitionSeconds(
                        from: prepositionFrame.jointRotations,
                        to: target.jointRotations
                    ) ?? .infinity
                )
                let constraintsOK = satisfiesKinematicConstraints(
                    hand: hand,
                    requiredContacts: prepositionContacts,
                    tipContactAllowances: prepositionContacts,
                    rootTransform: prepositionFrame.rootTransform,
                    jointRotations: prepositionFrame.jointRotations,
                    keyboardKeys: keyboardKeys
                )
                let firstTransitionOK = validatesTransition(
                    from: previous,
                    to: prepositionFrame,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: keyboardKeys
                )
                let secondTransitionOK = validatesTransition(
                    from: prepositionFrame,
                    to: target,
                    hand: hand,
                    contacts: contacts,
                    keyboardKeys: keyboardKeys
                )
                if firstRequired <= firstAvailable,
                   secondRequired <= secondAvailable,
                   constraintsOK,
                   firstTransitionOK,
                   secondTransitionOK
                {
                    return [prepositionFrame]
                }
            }
        }

        return clearanceArcFrames(
            from: previous,
            to: target,
            earliestStartSeconds: earliestStartSeconds,
            hand: hand,
            contacts: contacts,
            keyboardKeys: keyboardKeys
        )
    }

    private static func collisionAvoidanceIntermediateFrames(
        from lower: PianoHandMotionClip.Frame,
        to upper: PianoHandMotionClip.Frame,
        lowerJointAngles: [SIMD2<Float>],
        upperJointAngles: [SIMD2<Float>],
        hand: ScoreHand,
        contacts: [PlannedContact],
        adjustableFingers: Set<Int>,
        keyboardKeys: [KeyboardLayout.Key]
    ) -> [PianoHandMotionClip.Frame]? {
        let duration = upper.timeSeconds - lower.timeSeconds
        guard duration > 0,
              lowerJointAngles.count == upperJointAngles.count
        else {
            return nil
        }

        struct Candidate {
            let frame: PianoHandMotionClip.Frame
            let fromLowerOK: Bool
            let toUpperOK: Bool
        }
        var candidates: [Candidate] = []
        for progress: Float in [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8] {
            let midpointTime = lower.timeSeconds + duration * TimeInterval(progress)
            let requiredContacts = Self.activeContacts(in: contacts, at: midpointTime)
            let targets = requiredContacts.map {
                PianoDemonstrationHandRootPlanner.Target(
                    finger: $0.finger,
                    contactPositionLocal: $0.contactPositionLocal
                )
            }
            let firstAvailable = Float(midpointTime - lower.timeSeconds)
            let secondAvailable = Float(upper.timeSeconds - midpointTime)
            let midpointRoot = PianoHandMotionClip.RootTransform(
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
            )
            let initialAngles = zip(lowerJointAngles, upperJointAngles).map {
                simd_mix($0.0, $0.1, SIMD2<Float>(repeating: progress))
            }
            let bounds = JointTransitionBounds(
                previousJointAngles: lowerJointAngles,
                targetJointAngles: upperJointAngles,
                maximumFromPreviousRadians: firstAvailable
                    * Self.maximumJointAngularVelocityRadiansPerSecond,
                maximumToTargetRadians: secondAvailable
                    * Self.maximumJointAngularVelocityRadiansPerSecond
            )
            guard let pose = optimizePose(
                hand: hand,
                contacts: requiredContacts,
                targets: targets,
                initialJointAngles: initialAngles,
                initialRootTransform: midpointRoot,
                preserveRootHeight: true,
                preserveRootTranslation: true,
                adjustableFingers: adjustableFingers,
                jointTransitionBounds: bounds,
                keyboardKeys: keyboardKeys
            ) else {
                continue
            }
            let frame = PianoHandMotionClip.Frame(
                timeSeconds: midpointTime,
                rootTransform: pose.rootTransform,
                jointRotations: pose.jointAngles.map(Self.jointRotation)
            )
            let midpointConstraintsOK = satisfiesKinematicConstraints(
                hand: hand,
                requiredContacts: requiredContacts,
                tipContactAllowances: requiredContacts,
                rootTransform: frame.rootTransform,
                jointRotations: frame.jointRotations,
                keyboardKeys: keyboardKeys
            )
            let midpointFirstTransitionOK = validatesTransition(
                from: lower,
                to: frame,
                hand: hand,
                contacts: contacts,
                allowanceStartSeconds: lower.timeSeconds,
                keyboardKeys: keyboardKeys
            )
            let midpointSecondTransitionOK = validatesTransition(
                from: frame,
                to: upper,
                hand: hand,
                contacts: contacts,
                allowanceStartSeconds: lower.timeSeconds,
                keyboardKeys: keyboardKeys
            )
            let fromLowerSpeedOK = requiredWristTransitionSeconds(
                from: lower.rootTransform,
                to: frame.rootTransform
            ) <= firstAvailable && (requiredJointTransitionSeconds(
                from: lower.jointRotations,
                to: frame.jointRotations
            ) ?? .infinity) <= firstAvailable
            let toUpperSpeedOK = requiredWristTransitionSeconds(
                from: frame.rootTransform,
                to: upper.rootTransform
            ) <= secondAvailable && (requiredJointTransitionSeconds(
                from: frame.jointRotations,
                to: upper.jointRotations
            ) ?? .infinity) <= secondAvailable
            guard midpointConstraintsOK, fromLowerSpeedOK, toUpperSpeedOK else { continue }
            let candidate = Candidate(
                frame: frame,
                fromLowerOK: midpointFirstTransitionOK,
                toUpperOK: midpointSecondTransitionOK
            )
            if candidate.fromLowerOK && candidate.toUpperOK {
                return [candidate.frame]
            }
            candidates.append(candidate)
        }

        for early in candidates where early.fromLowerOK {
            for late in candidates where late.toUpperOK && late.frame.timeSeconds > early.frame.timeSeconds {
                let available = Float(late.frame.timeSeconds - early.frame.timeSeconds)
                guard requiredWristTransitionSeconds(
                    from: early.frame.rootTransform,
                    to: late.frame.rootTransform
                ) <= available,
                (requiredJointTransitionSeconds(
                    from: early.frame.jointRotations,
                    to: late.frame.jointRotations
                ) ?? .infinity) <= available,
                validatesTransition(
                    from: early.frame,
                    to: late.frame,
                    hand: hand,
                    contacts: contacts,
                    allowanceStartSeconds: lower.timeSeconds,
                    keyboardKeys: keyboardKeys
                )
                else {
                    continue
                }
                return [early.frame, late.frame]
            }
        }
        return nil
    }

    private static func clearanceArcFrames(
        from previous: PianoHandMotionClip.Frame,
        to target: PianoHandMotionClip.Frame,
        earliestStartSeconds: TimeInterval,
        hand: ScoreHand,
        contacts: [PlannedContact],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> [PianoHandMotionClip.Frame]? {
        let availableSeconds = Float(target.timeSeconds - earliestStartSeconds)
        guard availableSeconds > 0 else { return nil }
        let hasHeldContact = contacts.contains {
            $0.onsetSeconds < target.timeSeconds
                && $0.releaseSeconds > earliestStartSeconds
        }
        guard hasHeldContact == false else { return nil }

        let midpointRotation = simd_slerp(
            simd_quatf(vector: previous.rootTransform.rotation),
            simd_quatf(vector: target.rootTransform.rotation),
            0.5
        ).vector
        let midpointJointRotations = zip(previous.jointRotations, target.jointRotations).map { lower, upper in
            simd_slerp(simd_quatf(vector: lower), simd_quatf(vector: upper), 0.5).vector
        }
        let midpointTranslation = simd_mix(
            previous.rootTransform.translation,
            target.rootTransform.translation,
            SIMD3<Float>(repeating: 0.5)
        )
        let maximumApexLift = Self.maximumWristVelocityMetersPerSecond * availableSeconds / 2
        let searchSteps = 32

        for step in 1 ... searchSteps {
            let apexLift = maximumApexLift * Float(step) / Float(searchSteps)
            let apexRoot = PianoHandMotionClip.RootTransform(
                translation: midpointTranslation + SIMD3<Float>(0, apexLift, 0),
                rotation: midpointRotation
            )
            let firstSeconds = max(
                requiredWristTransitionSeconds(from: previous.rootTransform, to: apexRoot),
                requiredJointTransitionSeconds(
                    from: previous.jointRotations,
                    to: midpointJointRotations
                ) ?? .infinity
            )
            let secondSeconds = max(
                requiredWristTransitionSeconds(from: apexRoot, to: target.rootTransform),
                requiredJointTransitionSeconds(
                    from: midpointJointRotations,
                    to: target.jointRotations
                ) ?? .infinity
            )
            let totalSeconds = firstSeconds + secondSeconds
            guard totalSeconds <= availableSeconds else { continue }

            let routeStartSeconds = target.timeSeconds - TimeInterval(totalSeconds)
            let routeStart = PianoHandMotionClip.Frame(
                timeSeconds: routeStartSeconds,
                rootTransform: previous.rootTransform,
                jointRotations: previous.jointRotations
            )
            let apex = PianoHandMotionClip.Frame(
                timeSeconds: routeStartSeconds + TimeInterval(firstSeconds),
                rootTransform: apexRoot,
                jointRotations: midpointJointRotations
            )
            guard validatesTransition(
                from: routeStart,
                to: apex,
                hand: hand,
                contacts: contacts,
                allowanceStartSeconds: earliestStartSeconds,
                keyboardKeys: keyboardKeys
            ), validatesTransition(
                from: apex,
                to: target,
                hand: hand,
                contacts: contacts,
                allowanceStartSeconds: earliestStartSeconds,
                keyboardKeys: keyboardKeys
            ) else {
                continue
            }

            var route: [PianoHandMotionClip.Frame] = []
            if routeStartSeconds > previous.timeSeconds {
                route.append(routeStart)
            }
            route.append(apex)
            return route
        }
        return nil
    }

    private static func jointAngle(
        from start: SIMD2<Float>,
        toward target: SIMD2<Float>,
        maximumRotationRadians: Float
    ) -> SIMD2<Float> {
        guard maximumRotationRadians > 0 else { return start }
        let startRotation = Self.jointRotation(for: start)
        let targetRotation = Self.jointRotation(for: target)
        let totalDistance = Self.rotationDistanceRadians(from: startRotation, to: targetRotation)
        guard totalDistance > maximumRotationRadians else { return target }

        var lower: Float = 0
        var upper: Float = 1
        for _ in 0 ..< 14 {
            let progress = (lower + upper) / 2
            let candidate = simd_mix(start, target, SIMD2<Float>(repeating: progress))
            let distance = Self.rotationDistanceRadians(
                from: startRotation,
                to: Self.jointRotation(for: candidate)
            )
            if distance <= maximumRotationRadians {
                lower = progress
            } else {
                upper = progress
            }
        }
        return simd_mix(start, target, SIMD2<Float>(repeating: lower))
    }

    private static func requiredJointTransitionSeconds(
        from previous: [SIMD4<Float>],
        to target: [SIMD4<Float>]
    ) -> Float? {
        guard previous.count == target.count else { return nil }
        return zip(previous, target).reduce(into: Float.zero) { duration, pair in
            duration = max(
                duration,
                rotationDistanceRadians(from: pair.0, to: pair.1)
                    / Self.maximumJointAngularVelocityRadiansPerSecond
            )
        }
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
        var jointAngles = Self.neutralJointAngles()
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
        initialJointAngles: [SIMD2<Float>],
        preferredRootTransform: PianoHandMotionClip.RootTransform? = nil,
        keyboardKeys: [KeyboardLayout.Key]
    ) -> SolvedPose? {
        let targets = contacts.map {
            PianoDemonstrationHandRootPlanner.Target(
                finger: $0.finger,
                contactPositionLocal: $0.contactPositionLocal
            )
        }
        guard let baseRootTransform = PianoDemonstrationHandRootPlanner.rootTransform(
            for: hand,
            targets: targets
        ), initialJointAngles.count == PianoHandMotionClip.jointCount else {
            return nil
        }

        if let preferredRootTransform {
            let searchSteps = 16
            for step in 0 ... searchSteps {
                let progress = Float(step) / Float(searchSteps)
                let candidateRoot = PianoHandMotionClip.RootTransform(
                    translation: simd_mix(
                        preferredRootTransform.translation,
                        baseRootTransform.translation,
                        SIMD3(repeating: progress)
                    ),
                    rotation: simd_slerp(
                        simd_quatf(vector: preferredRootTransform.rotation),
                        simd_quatf(vector: baseRootTransform.rotation),
                        progress
                    ).vector
                )
                guard let preferredSolved = optimizePose(
                    hand: hand,
                    contacts: contacts,
                    targets: targets,
                    initialJointAngles: initialJointAngles,
                    initialRootTransform: candidateRoot,
                    preserveRootHeight: true,
                    preserveRootTranslation: true,
                    keyboardKeys: keyboardKeys
                ) else {
                    continue
                }
                let preferredRotations = preferredSolved.jointAngles.map(Self.jointRotation)
                if satisfiesKinematicConstraints(
                    hand: hand,
                    requiredContacts: contacts,
                    tipContactAllowances: contacts,
                    rootTransform: preferredSolved.rootTransform,
                    jointRotations: preferredRotations,
                    keyboardKeys: keyboardKeys
                ) {
                    return preferredSolved
                }
            }
        }

        guard let baseSolved = optimizePose(
            hand: hand,
            contacts: contacts,
            targets: targets,
            initialJointAngles: initialJointAngles,
            initialRootTransform: baseRootTransform,
            preserveRootHeight: true,
            keyboardKeys: keyboardKeys
        ) else {
            return nil
        }
        let baseRotations = baseSolved.jointAngles.map(Self.jointRotation)
        if satisfiesKinematicConstraints(
            hand: hand,
            requiredContacts: contacts,
            tipContactAllowances: contacts,
            rootTransform: baseSolved.rootTransform,
            jointRotations: baseRotations,
            keyboardKeys: keyboardKeys
        ) {
            return baseSolved
        }

        // Root height must be explored relative to an actual contact solution, not the unsolved
        // root guess. Otherwise the first positive lift also freezes the pre-IK vertical error.
        for rootLift: Float in stride(from: 0.003, through: 0.024, by: 0.003) {
            let candidateRoot = PianoHandMotionClip.RootTransform(
                translation: baseSolved.rootTransform.translation + SIMD3<Float>(0, rootLift, 0),
                rotation: baseSolved.rootTransform.rotation
            )
            guard let solved = optimizePose(
                hand: hand,
                contacts: contacts,
                targets: targets,
                initialJointAngles: baseSolved.jointAngles,
                initialRootTransform: candidateRoot,
                preserveRootHeight: true,
                keyboardKeys: keyboardKeys
            ) else {
                continue
            }
            let jointRotations = solved.jointAngles.map(Self.jointRotation)
            if satisfiesKinematicConstraints(
                hand: hand,
                requiredContacts: contacts,
                tipContactAllowances: contacts,
                rootTransform: solved.rootTransform,
                jointRotations: jointRotations,
                keyboardKeys: keyboardKeys
            ) {
                return solved
            }
        }
        return nil
    }

    private static func optimizePose(
        hand: ScoreHand,
        contacts: [PlannedContact],
        targets: [PianoDemonstrationHandRootPlanner.Target],
        initialJointAngles: [SIMD2<Float>],
        initialRootTransform: PianoHandMotionClip.RootTransform,
        preserveRootHeight: Bool,
        preserveRootTranslation: Bool = false,
        adjustableFingers: Set<Int>? = nil,
        jointTransitionBounds: JointTransitionBounds? = nil,
        keyboardKeys: [KeyboardLayout.Key]
    ) -> SolvedPose? {
        var rootTransform = initialRootTransform
        var jointAngles = initialJointAngles
        let alignedRoot: (PianoHandMotionClip.RootTransform, [SIMD2<Float>]) -> PianoHandMotionClip.RootTransform? = {
            candidateRoot, angles in
            if preserveRootTranslation {
                return candidateRoot
            }
            return PianoDemonstrationHandRootPlanner.alignedRootTransform(
                candidateRoot,
                hand: hand,
                targets: targets,
                jointRotations: angles.map(Self.jointRotation),
                preserveY: preserveRootHeight
            )
        }

        for step: Float in [0.32, 0.16, 0.08, 0.04, 0.02, 0.01] {
            for _ in 0 ..< 8 {
                guard let alignedRootTransform = alignedRoot(rootTransform, jointAngles) else {
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

        guard var alignedRootTransform = alignedRoot(rootTransform, jointAngles) else {
            return nil
        }

        // Contact-only IK is under-constrained: it can place intermediate joints inside the key
        // bed. A second deterministic descent optimizes only the fingers this pose is allowed to move.
        let fingersToOptimize = (adjustableFingers ?? Set(contacts.map(\.finger))).sorted()
        for step: Float in [0.24, 0.12, 0.06, 0.03, 0.015] {
            for _ in 0 ..< 5 {
                for finger in fingersToOptimize {
                    let startIndex = 1 + (finger - 1) * 4
                    for jointIndex in startIndex ..< startIndex + 3 {
                        for component in 0 ... 1 {
                            let original = jointAngles[jointIndex][component]
                            var bestValue = original
                            var bestRoot = alignedRootTransform
                            var bestCost = poseCost(
                                hand: hand,
                                contacts: contacts,
                                rootTransform: alignedRootTransform,
                                jointAngles: jointAngles,
                                keyboardKeys: keyboardKeys
                            )
                            for candidate in [original - step, original + step] {
                                let constrained = constrainedJointAngle(
                                    candidate,
                                    component: component,
                                    finger: finger
                                )
                                jointAngles[jointIndex][component] = constrained
                                if let jointTransitionBounds,
                                   Self.satisfiesJointTransitionBound(
                                       jointAngles[jointIndex],
                                       index: jointIndex,
                                       bounds: jointTransitionBounds
                                   ) == false
                                {
                                    jointAngles[jointIndex][component] = original
                                    continue
                                }
                                guard let candidateRoot = alignedRoot(alignedRootTransform, jointAngles) else {
                                    jointAngles[jointIndex][component] = original
                                    continue
                                }
                                let cost = poseCost(
                                    hand: hand,
                                    contacts: contacts,
                                    rootTransform: candidateRoot,
                                    jointAngles: jointAngles,
                                    keyboardKeys: keyboardKeys
                                )
                                if cost < bestCost {
                                    bestCost = cost
                                    bestValue = constrained
                                    bestRoot = candidateRoot
                                }
                            }
                            jointAngles[jointIndex][component] = bestValue
                            alignedRootTransform = bestRoot
                        }
                    }
                }
            }
        }

        let finalErrors = contacts.map {
            Self.contactErrorSquared(
                for: $0,
                hand: hand,
                rootTransform: alignedRootTransform,
                jointAngles: jointAngles
            )
        }
        guard finalErrors.allSatisfy({ $0 <= pow(Self.maximumContactErrorMeters, 2) }) else {
            return nil
        }
        if let jointTransitionBounds,
           Self.satisfiesJointTransitionBounds(jointAngles, bounds: jointTransitionBounds) == false
        {
            return nil
        }
        return SolvedPose(rootTransform: alignedRootTransform, jointAngles: jointAngles)
    }

    private static func satisfiesJointTransitionBound(
        _ jointAngle: SIMD2<Float>,
        index: Int,
        bounds: JointTransitionBounds
    ) -> Bool {
        guard bounds.previousJointAngles.indices.contains(index),
              bounds.targetJointAngles.indices.contains(index)
        else {
            return false
        }
        let currentRotation = Self.jointRotation(for: jointAngle)
        let previousRotation = Self.jointRotation(for: bounds.previousJointAngles[index])
        let targetRotation = Self.jointRotation(for: bounds.targetJointAngles[index])
        return Self.rotationDistanceRadians(from: previousRotation, to: currentRotation)
                <= bounds.maximumFromPreviousRadians + 0.000_1
            && Self.rotationDistanceRadians(from: currentRotation, to: targetRotation)
                <= bounds.maximumToTargetRadians + 0.000_1
    }

    private static func satisfiesJointTransitionBounds(
        _ jointAngles: [SIMD2<Float>],
        bounds: JointTransitionBounds
    ) -> Bool {
        guard jointAngles.count == bounds.previousJointAngles.count,
              jointAngles.count == bounds.targetJointAngles.count
        else {
            return false
        }
        return jointAngles.indices.allSatisfy {
            Self.satisfiesJointTransitionBound(jointAngles[$0], index: $0, bounds: bounds)
        }
    }

    private static func poseCost(
        hand: ScoreHand,
        contacts: [PlannedContact],
        rootTransform: PianoHandMotionClip.RootTransform,
        jointAngles: [SIMD2<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Float {
        var contactErrors: [Float] = []
        contactErrors.reserveCapacity(contacts.count)
        for contact in contacts {
            guard let tip = PianoDemonstrationHandSkeleton.fingerJointPositions(
                finger: contact.finger,
                hand: hand,
                rootTransform: rootTransform,
                jointRotations: jointAngles.map(Self.jointRotation)
            )?.last else {
                return .greatestFiniteMagnitude
            }
            contactErrors.append(simd_distance_squared(tip, contact.contactPositionLocal))
        }
        let contactCost = contactErrors.reduce(0, +)
        let collisionCost = keyboardCollisionPenalty(
            hand: hand,
            contacts: contacts,
            rootTransform: rootTransform,
            jointRotations: jointAngles.map(Self.jointRotation),
            keyboardKeys: keyboardKeys
        )
        return contactCost + collisionCost * 4
    }

    private static func keyboardCollisionPenalty(
        hand: ScoreHand,
        contacts: [PlannedContact],
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Float {
        guard let positions = PianoDemonstrationHandSkeleton.jointPositions(
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        ), positions.indices.contains(20) else {
            return .greatestFiniteMagnitude
        }
        let contactsByFinger = Dictionary(uniqueKeysWithValues: contacts.map { ($0.finger, $0) })
        var capsules: [FingerCapsule] = []
        for finger in 1 ... 5 {
            let start = 1 + (finger - 1) * 4
            let joints = Array(positions[start ... start + 3])
            capsules += zip(joints, joints.dropFirst()).enumerated().map { segmentIndex, segment in
                FingerCapsule(
                    finger: finger,
                    segmentIndex: segmentIndex,
                    capsule: Capsule(start: segment.0, end: segment.1, radius: Self.fingerCapsuleRadiusMeters),
                    targetKey: contactsByFinger[finger]?.key,
                    allowsTipContact: contactsByFinger[finger] != nil && segmentIndex == 2
                )
            }
        }
        let palm = Capsule(start: positions[1], end: positions[17], radius: Self.palmCapsuleRadiusMeters)
        var penalty: Float = 0
        for key in keyboardKeys where palm.overlapsHorizontally(key) {
            let penetration = max(
                0,
                key.surfaceLocalY + palm.radius + Self.collisionClearanceMeters
                    - min(palm.start.y, palm.end.y)
            )
            penalty += penetration * penetration
        }
        for finger in capsules {
            for key in keyboardKeys {
                let capsule = finger.allowsTipContact && finger.targetKey?.midiNote == key.midiNote
                    ? finger.capsule.trimmedBeforeTipContact(on: key, clearance: Self.collisionClearanceMeters)
                    : finger.capsule
                guard let capsule, capsule.overlapsHorizontally(key) else { continue }
                let penetration = max(
                    0,
                    key.surfaceLocalY + capsule.radius + Self.collisionClearanceMeters
                        - min(capsule.start.y, capsule.end.y)
                )
                penalty += penetration * penetration
            }
        }
        for leftIndex in capsules.indices {
            for rightIndex in capsules.indices.dropFirst(leftIndex + 1)
                where capsules[leftIndex].finger != capsules[rightIndex].finger
            {
                let left = capsules[leftIndex].capsule
                let right = capsules[rightIndex].capsule
                let distance = sqrt(Self.segmentDistanceSquared(
                    from: left.start,
                    to: left.end,
                    and: right.start,
                    to: right.end
                ))
                let overlap = max(0, left.radius + right.radius - distance)
                penalty += overlap * overlap
            }
        }
        return penalty
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
            let minimum = finger == 1
                ? -Self.maximumThumbExtensionRadians
                : -Self.maximumFingerExtensionRadians
            return min(max(value, minimum), maximum)
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

    private static func neutralJointAngles() -> [SIMD2<Float>] {
        var jointAngles = Array(
            repeating: SIMD2<Float>.zero,
            count: PianoHandMotionClip.jointCount
        )
        for finger in 1 ... 5 {
            let isThumb = finger == 1
            let flexion: Float = isThumb ? 0.25 : 0.35
            let weights: [Float] = isThumb
                ? [0.32, 0.42, 0.20, 0.06]
                : [0.18, 0.42, 0.28, 0.12]
            let startIndex = 1 + (finger - 1) * 4
            for (offset, weight) in weights.enumerated() {
                jointAngles[startIndex + offset] = SIMD2(flexion * weight, 0)
            }
        }
        return jointAngles
    }

    private static func jointRotation(for angles: SIMD2<Float>) -> SIMD4<Float> {
        let flexion = simd_quatf(angle: -angles.x, axis: SIMD3<Float>(1, 0, 0))
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

    private static func minimumClearanceRootTransform(
        _ rootTransform: PianoHandMotionClip.RootTransform,
        hand: ScoreHand,
        jointRotations: [SIMD4<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> PianoHandMotionClip.RootTransform? {
        guard let correction = requiredClearanceLift(
            rootTransform: rootTransform,
            hand: hand,
            jointRotations: jointRotations,
            keyboardKeys: keyboardKeys
        ) else {
            return nil
        }
        let translation = rootTransform.translation + SIMD3<Float>(0, correction, 0)
        guard Self.isFinite(translation) else { return nil }
        return .init(translation: translation, rotation: rootTransform.rotation)
    }

    private static func requiredClearanceLift(
        rootTransform: PianoHandMotionClip.RootTransform,
        hand: ScoreHand,
        jointRotations: [SIMD4<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Float? {
        guard let positions = PianoDemonstrationHandSkeleton.jointPositions(
            hand: hand,
            rootTransform: rootTransform,
            jointRotations: jointRotations
        ), positions.indices.contains(20) else {
            return nil
        }

        var capsules: [Capsule] = [
            Capsule(start: positions[1], end: positions[17], radius: Self.palmCapsuleRadiusMeters),
        ]
        for finger in 1 ... 5 {
            let start = 1 + (finger - 1) * 4
            let joints = Array(positions[start ... start + 3])
            capsules += zip(joints, joints.dropFirst()).map {
                Capsule(start: $0.0, end: $0.1, radius: Self.fingerCapsuleRadiusMeters)
            }
        }

        return max(0, capsules.reduce(into: Float.zero) { lift, capsule in
            for key in keyboardKeys where capsule.overlapsHorizontally(key) {
                lift = max(
                    lift,
                    key.surfaceLocalY + capsule.radius + Self.collisionClearanceMeters
                        - min(capsule.start.y, capsule.end.y)
                )
            }
        })
    }

    private static func satisfiesKinematicConstraints(
        hand: ScoreHand,
        requiredContacts: [PlannedContact],
        tipContactAllowances: [PlannedContact],
        rootTransform: PianoHandMotionClip.RootTransform,
        jointRotations: [SIMD4<Float>],
        keyboardKeys: [KeyboardLayout.Key]
    ) -> Bool {
        guard jointRotations.count == PianoHandMotionClip.jointCount else {
            return false
        }
        guard jointRotations.allSatisfy(Self.isValidRotation) else {
            return false
        }
        guard keyboardKeys.allSatisfy(Self.isValid) else {
            return false
        }
        guard Set(requiredContacts.map(\.finger)).count == requiredContacts.count,
              Set(tipContactAllowances.map(\.finger)).count == tipContactAllowances.count
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

        let requiredContactsByFinger = Dictionary(
            uniqueKeysWithValues: requiredContacts.map { ($0.finger, $0) }
        )
        let tipContactAllowancesByFinger = Dictionary(
            uniqueKeysWithValues: tipContactAllowances.map { ($0.finger, $0) }
        )
        let fingers = (1 ... 5).compactMap { finger -> FingerGeometry? in
            let start = 1 + (finger - 1) * 4
            guard positions.indices.contains(start + 3) else { return nil }
            let joints = Array(positions[start ... start + 3])
            guard Self.hasValidBoneLengths(joints, finger: finger, hand: hand)
            else {
                return nil
            }
            if let contact = requiredContactsByFinger[finger], Self.isValidTipContact(contact, tip: joints[3]) == false {
                return nil
            }
            return FingerGeometry(
                finger: finger,
                joints: joints,
                targetKey: tipContactAllowancesByFinger[finger]?.key
            )
        }
        guard fingers.count == 5 else {
            return false
        }

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
        guard Self.hasNoFingerSelfIntersections(fingerCapsules, palm: palm) else {
            return false
        }
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
            abs(tip.x - key.topSurfaceCenterLocal.x),
            abs(tip.z - key.topSurfaceCenterLocal.y)
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
                    ? finger.capsule.trimmedBeforeTipContact(on: key, clearance: Self.collisionClearanceMeters)
                    : finger.capsule
                guard let capsule else { continue }
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

    private struct JointTransitionBounds {
        let previousJointAngles: [SIMD2<Float>]
        let targetJointAngles: [SIMD2<Float>]
        let maximumFromPreviousRadians: Float
        let maximumToTargetRadians: Float
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

        /// The terminal skeleton joint is the key-surface contact point, not the centre of a
        /// spherical fingertip. On the intended key, keep only the full-radius part of the distal
        /// segment that remains above the key; the remaining taper is represented by the contact point.
        func trimmedBeforeTipContact(
            on key: KeyboardLayout.Key,
            clearance: Float
        ) -> Self? {
            let safeY = key.surfaceLocalY + radius + clearance
            guard end.y < safeY else { return self }
            guard start.y > safeY else { return nil }
            let verticalTravel = start.y - end.y
            guard verticalTravel > 0.000_001 else { return nil }
            let progress = (start.y - safeY) / verticalTravel
            guard progress > 0, progress < 1 else { return nil }
            return Self(
                start: start,
                end: start + (end - start) * progress,
                radius: radius
            )
        }

        func overlapsHorizontally(_ key: KeyboardLayout.Key) -> Bool {
            let halfSize = key.topSurfaceSizeLocal / 2 + SIMD2(repeating: radius)
            let minimum = SIMD2(min(start.x, end.x), min(start.z, end.z))
            let maximum = SIMD2(max(start.x, end.x), max(start.z, end.z))
            let keyMinimum = key.topSurfaceCenterLocal - halfSize
            let keyMaximum = key.topSurfaceCenterLocal + halfSize
            return minimum.x <= keyMaximum.x
                && maximum.x >= keyMinimum.x
                && minimum.y <= keyMaximum.y
                && maximum.y >= keyMinimum.y
        }

        func intersectsKeyboard(_ key: KeyboardLayout.Key) -> Bool {
            let halfSize = key.topSurfaceSizeLocal / 2 + SIMD2(repeating: radius)
            let minimum = SIMD3(
                key.topSurfaceCenterLocal.x - halfSize.x,
                -Float.greatestFiniteMagnitude,
                key.topSurfaceCenterLocal.y - halfSize.y
            )
            let maximum = SIMD3(
                key.topSurfaceCenterLocal.x + halfSize.x,
                key.surfaceLocalY + radius,
                key.topSurfaceCenterLocal.y + halfSize.y
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
    private static let wristHeightMeters: Float = 0.045

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
        let surfaceY = targets.map(\.contactPositionLocal.y).max() ?? 0
        return alignedRootTransform(
            .init(
                translation: SIMD3<Float>(0, surfaceY + Self.wristHeightMeters, 0),
                rotation: rotation
            ),
            hand: hand,
            targets: targets,
            jointRotations: restRotations,
            preserveY: true
        )
    }

    static func alignedRootTransform(
        _ rootTransform: PianoHandMotionClip.RootTransform,
        hand: ScoreHand,
        targets: [Target],
        jointRotations: [SIMD4<Float>],
        preserveY: Bool = false
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
        let correction = preserveY
            ? SIMD3<Float>(translationCorrection.x, 0, translationCorrection.z)
            : translationCorrection
        let translation = rootTransform.translation + correction
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
        let keyboardFacingRotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        return (yawRotation * keyboardFacingRotation).vector
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
