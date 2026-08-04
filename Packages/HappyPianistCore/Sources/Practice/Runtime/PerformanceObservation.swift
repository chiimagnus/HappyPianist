import Foundation
import MusicXML

public struct PerformanceObservation: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Hashable, Sendable {
        public enum Role: String, Codable, Sendable {
            case userPerformance
            case systemPlayback
        }

        public enum Kind: String, Codable, Sendable {
            case midi1
            case midi2
            case targetAudio
            case realPianoContact
            case virtualPianoContact
        }

        public let kind: Kind
        public let id: String
        public let generation: UInt64
        public let capabilities: PerformanceInputCapabilities
        public let role: Role

        public init(
            kind: Kind,
            id: String,
            generation: UInt64,
            capabilities: PerformanceInputCapabilities? = nil,
            role: Role = .userPerformance
        ) {
            self.kind = kind
            self.id = id
            self.generation = generation
            self.capabilities = capabilities ?? kind.defaultCapabilities
            self.role = role
        }
    }

    public struct NormalizedValue: Codable, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public init(midi1 value: Int) {
            let clamped = UInt32(max(0, min(127, value)))
            self.rawValue = clamped * (UInt32.max / 127) + clamped * (UInt32.max % 127) / 127
        }

        public init(midi2 value: UInt16) {
            self.rawValue = UInt32(value) * 65537
        }

        public init(midi14 value: Int) {
            let clamped = UInt32(max(0, min(16383, value)))
            self.rawValue = clamped * (UInt32.max / 16383) + clamped * (UInt32.max % 16383) / 16383
        }
    }

    public enum Controller: Codable, Equatable, Sendable {
        case controlChange(number: Int, value: NormalizedValue)
        case pitchBend(value: NormalizedValue)
        case programChange(program: Int)
        case channelPressure(value: NormalizedValue)
        case polyPressure(note: Int, value: NormalizedValue)
    }

    public enum ContactPhase: String, Codable, Sendable {
        case started
        case held
        case ended
    }

    public enum TargetAudioDetectionResult: String, Codable, Sendable {
        case detected
        case contradicted
        case mixed
        case unknown
    }

    public enum Event: Codable, Equatable, Sendable {
        case noteOn(note: Int, velocity: NormalizedValue?)
        case noteOff(note: Int, releaseVelocity: NormalizedValue?)
        case controller(Controller)
        case contact(id: String, keyCandidate: Int?, phase: ContactPhase)
        case targetAudioDetection(
            targetMIDINotes: [Int],
            detectedMIDINotes: [Int],
            result: TargetAudioDetectionResult
        )
    }

    public let id: UUID
    public let source: Source
    public let timing: PerformanceClockReading
    public let event: Event
    public let onsetVelocity: NormalizedValue?
    public let channel: Int?
    public let group: Int?
    public let hand: ScoreHand?
    public let finger: Int?
    public let confidence: Double?
    public let calibrationReference: String?

    public init(
        id: UUID = UUID(),
        source: Source,
        timing: PerformanceClockReading,
        event: Event,
        onsetVelocity: NormalizedValue? = nil,
        channel: Int? = nil,
        group: Int? = nil,
        hand: ScoreHand? = nil,
        finger: Int? = nil,
        confidence: Double? = nil,
        calibrationReference: String? = nil
    ) {
        self.id = id
        self.source = source
        self.timing = timing
        self.event = event
        if let onsetVelocity {
            self.onsetVelocity = onsetVelocity
        } else if case let .noteOn(_, velocity) = event {
            self.onsetVelocity = velocity
        } else {
            self.onsetVelocity = nil
        }
        self.channel = channel.map { max(1, min(16, $0)) }
        self.group = group.map { max(0, min(15, $0)) }
        self.hand = hand
        self.finger = finger.map { max(1, min(5, $0)) }
        self.confidence = confidence.map { max(0, min(1, $0)) }
        self.calibrationReference = calibrationReference
    }

    public var alignmentTimestamp: PerformanceMonotonicInstant {
        timing.correctedHost
    }
}
