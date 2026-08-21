import Foundation
import MusicXML

/// A validated, keyboard-local animation candidate for one planned hand.
///
/// Joint translations are intentionally absent: a clip may move the hand root, but it
/// can only rotate the authored 21-joint skeleton.
public struct PianoHandMotionClip: Equatable, Sendable {
    public static let jointCount = 21

    public enum ValidationError: Error, Equatable, Sendable {
        case emptyFrames
        case invalidFrameTime
        case unorderedFrames
        case invalidRootTransform
        case invalidJointCount
        case invalidJointRotation
        case invalidCoverage
    }

    public struct Metadata: Equatable, Sendable {
        public let formatVersion: Int
        public let generatorRevision: String
        public let skeletonRevision: String
        public let scoreRevision: String

        public init(
            formatVersion: Int = 1,
            generatorRevision: String,
            skeletonRevision: String,
            scoreRevision: String
        ) {
            self.formatVersion = formatVersion
            self.generatorRevision = generatorRevision
            self.skeletonRevision = skeletonRevision
            self.scoreRevision = scoreRevision
        }
    }

    public struct RootTransform: Equatable, Sendable {
        public let translation: SIMD3<Float>
        public let rotation: SIMD4<Float>

        public init(translation: SIMD3<Float>, rotation: SIMD4<Float>) {
            self.translation = translation
            self.rotation = rotation
        }
    }

    public struct Frame: Equatable, Sendable {
        public let timeSeconds: TimeInterval
        public let rootTransform: RootTransform
        public let jointRotations: [SIMD4<Float>]

        public init(
            timeSeconds: TimeInterval,
            rootTransform: RootTransform,
            jointRotations: [SIMD4<Float>]
        ) {
            self.timeSeconds = timeSeconds
            self.rootTransform = rootTransform
            self.jointRotations = jointRotations
        }
    }

    public struct Coverage: Equatable, Identifiable, Sendable {
        public let occurrenceID: String
        public let finger: Int
        public let onsetSeconds: TimeInterval
        public let releaseSeconds: TimeInterval

        public var id: String {
            occurrenceID
        }

        public init(
            occurrenceID: String,
            finger: Int,
            onsetSeconds: TimeInterval,
            releaseSeconds: TimeInterval
        ) {
            self.occurrenceID = occurrenceID
            self.finger = finger
            self.onsetSeconds = onsetSeconds
            self.releaseSeconds = releaseSeconds
        }
    }

    public let metadata: Metadata
    public let hand: ScoreHand
    public let frames: [Frame]
    public let coverage: [Coverage]

    public init(
        metadata: Metadata,
        hand: ScoreHand,
        frames: [Frame],
        coverage: [Coverage]
    ) throws {
        guard frames.isEmpty == false else { throw ValidationError.emptyFrames }
        guard hand == .left || hand == .right else { throw ValidationError.invalidCoverage }
        guard coverage.allSatisfy(Self.isValidCoverage),
              Set(coverage.map(\.occurrenceID)).count == coverage.count
        else {
            throw ValidationError.invalidCoverage
        }

        var previousTime: TimeInterval?
        for frame in frames {
            guard frame.timeSeconds.isFinite else { throw ValidationError.invalidFrameTime }
            guard previousTime.map({ frame.timeSeconds > $0 }) ?? true else {
                throw ValidationError.unorderedFrames
            }
            guard Self.isFinite(frame.rootTransform.translation),
                  Self.isValidRotation(frame.rootTransform.rotation)
            else {
                throw ValidationError.invalidRootTransform
            }
            guard frame.jointRotations.count == Self.jointCount else {
                throw ValidationError.invalidJointCount
            }
            guard frame.jointRotations.allSatisfy(Self.isValidRotation) else {
                throw ValidationError.invalidJointRotation
            }
            previousTime = frame.timeSeconds
        }

        self.metadata = metadata
        self.hand = hand
        self.frames = frames
        self.coverage = coverage.sorted { $0.occurrenceID < $1.occurrenceID }
    }

    /// Returns the previous frame in range and clamps out-of-range sampling to an endpoint.
    public func frame(at timeSeconds: TimeInterval) -> Frame {
        guard timeSeconds.isFinite else {
            return timeSeconds.sign == .minus ? frames[0] : frames[frames.count - 1]
        }
        guard timeSeconds > frames[0].timeSeconds else { return frames[0] }
        guard timeSeconds < frames[frames.count - 1].timeSeconds else { return frames[frames.count - 1] }

        var lowerBound = 0
        var upperBound = frames.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if frames[midpoint].timeSeconds <= timeSeconds {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        return frames[lowerBound - 1]
    }

    private static func isValidCoverage(_ coverage: Coverage) -> Bool {
        coverage.occurrenceID.isEmpty == false
            && (1 ... 5).contains(coverage.finger)
            && coverage.onsetSeconds.isFinite
            && coverage.releaseSeconds.isFinite
            && coverage.releaseSeconds >= coverage.onsetSeconds
    }

    private static func isFinite(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func isValidRotation(_ rotation: SIMD4<Float>) -> Bool {
        guard rotation.x.isFinite,
              rotation.y.isFinite,
              rotation.z.isFinite,
              rotation.w.isFinite
        else {
            return false
        }
        let magnitudeSquared = rotation.x * rotation.x
            + rotation.y * rotation.y
            + rotation.z * rotation.z
            + rotation.w * rotation.w
        return magnitudeSquared.isFinite && abs(magnitudeSquared - 1) <= 0.001
    }
}
