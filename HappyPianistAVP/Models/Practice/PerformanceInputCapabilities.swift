struct PerformanceInputCapabilities: Codable, Equatable, Hashable, Sendable {
    enum Evidence: String, Codable, Sendable {
        case observed
        case unavailable
        case degraded

        func merging(_ other: Self) -> Self {
            if self == .observed || other == .observed { return .observed }
            if self == .degraded || other == .degraded { return .degraded }
            return .unavailable
        }
    }

    let pitch: Evidence
    let onset: Evidence
    let release: Evidence
    let velocity: Evidence
    let controllers: Evidence
    let polyphony: Evidence
    let hand: Evidence
    let finger: Evidence
    let position: Evidence
    let confidence: Evidence

    static let unavailable = Self(
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

    static let midi = Self(
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

    static let targetAudio = Self(
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

    static let handContact = Self(
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

    func merging(_ other: Self) -> Self {
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
