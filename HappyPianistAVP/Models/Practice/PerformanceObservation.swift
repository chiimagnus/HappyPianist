import Foundation

struct PerformanceObservation: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            case midi1
            case midi2
            case targetAudio
            case realPianoContact
            case virtualPianoContact
        }

        let kind: Kind
        let id: String
        let generation: UInt64
        let capabilities: PerformanceInputCapabilities

        init(
            kind: Kind,
            id: String,
            generation: UInt64,
            capabilities: PerformanceInputCapabilities? = nil
        ) {
            self.kind = kind
            self.id = id
            self.generation = generation
            self.capabilities = capabilities ?? kind.defaultCapabilities
        }
    }

    struct NormalizedValue: Codable, Equatable, Sendable {
        let rawValue: UInt32

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        init(midi1 value: Int) {
            let clamped = UInt32(max(0, min(127, value)))
            self.rawValue = clamped * (UInt32.max / 127) + clamped * (UInt32.max % 127) / 127
        }

        init(midi2 value: UInt16) {
            self.rawValue = UInt32(value) * 65_537
        }

        init(midi14 value: Int) {
            let clamped = UInt32(max(0, min(16_383, value)))
            self.rawValue = clamped * (UInt32.max / 16_383) + clamped * (UInt32.max % 16_383) / 16_383
        }
    }

    enum Controller: Codable, Equatable, Sendable {
        case controlChange(number: Int, value: NormalizedValue)
        case pitchBend(value: NormalizedValue)
        case programChange(program: Int)
        case channelPressure(value: NormalizedValue)
        case polyPressure(note: Int, value: NormalizedValue)
    }

    enum ContactPhase: String, Codable, Sendable {
        case started
        case held
        case ended
    }

    enum TargetAudioDetectionResult: String, Codable, Sendable {
        case detected
        case contradicted
        case mixed
        case unknown
    }

    enum Event: Codable, Equatable, Sendable {
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

    let id: UUID
    let source: Source
    let timing: PerformanceClockReading
    let event: Event
    let channel: Int?
    let group: Int?
    let hand: ScoreHand?
    let finger: Int?
    let confidence: Double?
    let calibrationReference: String?

    init(
        id: UUID = UUID(),
        source: Source,
        timing: PerformanceClockReading,
        event: Event,
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
        self.channel = channel.map { max(1, min(16, $0)) }
        self.group = group.map { max(0, min(15, $0)) }
        self.hand = hand
        self.finger = finger.map { max(1, min(5, $0)) }
        self.confidence = confidence.map { max(0, min(1, $0)) }
        self.calibrationReference = calibrationReference
    }

    var alignmentTimestamp: PerformanceMonotonicInstant {
        timing.correctedHost
    }
}
