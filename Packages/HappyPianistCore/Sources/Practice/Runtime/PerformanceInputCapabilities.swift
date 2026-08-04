public struct PerformanceInputCapabilities: Codable, Equatable, Hashable, Sendable {
    public enum Evidence: String, Codable, Sendable {
        case observed
        case unavailable
        case degraded

        func merging(_ other: Self) -> Self {
            if self == .observed || other == .observed { return .observed }
            if self == .degraded || other == .degraded { return .degraded }
            return .unavailable
        }
    }

    public let pitch: Evidence
    public let onset: Evidence
    public let release: Evidence
    public let velocity: Evidence
    public let controllers: Evidence
    public let polyphony: Evidence
    public let hand: Evidence
    public let finger: Evidence
    public let position: Evidence
    public let confidence: Evidence

    public init(
        pitch: Evidence,
        onset: Evidence,
        release: Evidence,
        velocity: Evidence,
        controllers: Evidence,
        polyphony: Evidence,
        hand: Evidence,
        finger: Evidence,
        position: Evidence,
        confidence: Evidence
    ) {
        self.pitch = pitch
        self.onset = onset
        self.release = release
        self.velocity = velocity
        self.controllers = controllers
        self.polyphony = polyphony
        self.hand = hand
        self.finger = finger
        self.position = position
        self.confidence = confidence
    }

    public static let unavailable = Self(
        pitch: .unavailable,
        onset: .unavailable,
        release: .unavailable,
        velocity: .unavailable,
        controllers: .unavailable,
        polyphony: .unavailable,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .unavailable
    )

    public static let midi = Self(
        pitch: .observed,
        onset: .observed,
        release: .observed,
        velocity: .observed,
        controllers: .observed,
        polyphony: .observed,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .unavailable
    )

    public static let targetAudio = Self(
        pitch: .degraded,
        onset: .degraded,
        release: .unavailable,
        velocity: .unavailable,
        controllers: .unavailable,
        polyphony: .degraded,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .observed
    )

    public static let handContact = Self(
        pitch: .degraded,
        onset: .observed,
        release: .observed,
        velocity: .degraded,
        controllers: .unavailable,
        polyphony: .observed,
        hand: .observed,
        finger: .observed,
        position: .observed,
        confidence: .observed
    )

    public func merging(_ other: Self) -> Self {
        Self(
            pitch: pitch.merging(other.pitch),
            onset: onset.merging(other.onset),
            release: release.merging(other.release),
            velocity: velocity.merging(other.velocity),
            controllers: controllers.merging(other.controllers),
            polyphony: polyphony.merging(other.polyphony),
            hand: hand.merging(other.hand),
            finger: finger.merging(other.finger),
            position: position.merging(other.position),
            confidence: confidence.merging(other.confidence)
        )
    }
}

extension PerformanceObservation.Source.Kind {
    var defaultCapabilities: PerformanceInputCapabilities {
        switch self {
        case .midi1, .midi2:
            .midi
        case .targetAudio:
            .targetAudio
        case .realPianoContact, .virtualPianoContact:
            .handContact
        }
    }
}
