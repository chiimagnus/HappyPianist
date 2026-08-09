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
        let identityRotation = SIMD4<Float>(0, 0, 0, 1)
        var previousJointAngles = Array(
            repeating: SIMD2<Float>.zero,
            count: PianoHandMotionClip.jointCount
        )
        var previousOnset: TimeInterval?
        let frames = try contactsByOnset.keys.sorted().map { onsetSeconds in
            try Task.checkCancellation()
            let contactsAtOnset = contactsByOnset[onsetSeconds] ?? []
            let averagePosition = contactsAtOnset.reduce(into: SIMD3<Float>.zero) { position, contact in
                position += contact.contactPositionLocal
            } / Float(contactsAtOnset.count)
            guard let targetJointAngles = Self.targetJointAngles(
                for: contactsAtOnset,
                palmCenter: averagePosition,
                hand: hand
            )
            else {
                throw MotionConstraintError()
            }
            let maximumDelta = previousOnset.map {
                max(0, Float(onsetSeconds - $0) * Self.maximumJointAngularVelocityRadiansPerSecond)
            } ?? .infinity
            guard zip(previousJointAngles, targetJointAngles).allSatisfy({ previous, target in
                Self.isWithinAngularVelocityLimit(
                    from: previous,
                    to: target,
                    maximumDelta: maximumDelta
                )
            }) else {
                throw MotionConstraintError()
            }
            previousJointAngles = targetJointAngles
            previousOnset = onsetSeconds

            return PianoHandMotionClip.Frame(
                timeSeconds: onsetSeconds,
                rootTransform: .init(
                    translation: averagePosition + SIMD3<Float>(0, 0.045, 0.050),
                    rotation: identityRotation
                ),
                jointRotations: targetJointAngles.map { Self.jointRotation(for: $0) }
            )
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
