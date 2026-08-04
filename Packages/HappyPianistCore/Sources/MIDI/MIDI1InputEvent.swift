import Foundation

public struct MIDI1InputEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case noteOn(note: Int, velocity: Int)
        case noteOff(note: Int, velocity: Int)
        case controlChange(controller: Int, value: Int)
        case pitchBend(value: Int)
        case programChange(program: Int)
        case channelPressure(value: Int)
        case polyPressure(note: Int, value: Int)
    }

    /// Stable while the same raw input event is routed to matching, recording, and AI.
    public let observationID: UUID
    public let kind: Kind
    public let channel: Int
    public let group: Int
    public let source: MIDIInputSource
    public let receivedAt: Date
    public let receivedAtUptimeSeconds: TimeInterval
    public let sourceTimestamp: PerformanceSourceTimestamp?

    public init(
        observationID: UUID = UUID(),
        kind: Kind,
        channel: Int,
        group: Int,
        source: MIDIInputSource,
        receivedAt: Date,
        receivedAtUptimeSeconds: TimeInterval,
        sourceTimestamp: PerformanceSourceTimestamp? = nil
    ) {
        self.observationID = observationID
        self.kind = Self.clamp(kind)
        self.channel = Self.clamp(channel, min: 1, max: 16)
        self.group = Self.clamp(group, min: 0, max: 15)
        self.source = source
        self.receivedAt = receivedAt
        self.receivedAtUptimeSeconds = max(0, receivedAtUptimeSeconds)
        self.sourceTimestamp = sourceTimestamp
    }

    private static func clamp(_ kind: Kind) -> Kind {
        switch kind {
        case let .noteOn(note, velocity):
            .noteOn(
                note: clamp(note, min: 0, max: 127),
                velocity: clamp(velocity, min: 0, max: 127)
            )
        case let .noteOff(note, velocity):
            .noteOff(
                note: clamp(note, min: 0, max: 127),
                velocity: clamp(velocity, min: 0, max: 127)
            )
        case let .controlChange(controller, value):
            .controlChange(
                controller: clamp(controller, min: 0, max: 127),
                value: clamp(value, min: 0, max: 127)
            )
        case let .pitchBend(value):
            .pitchBend(value: clamp(value, min: 0, max: 16383))
        case let .programChange(program):
            .programChange(program: clamp(program, min: 0, max: 127))
        case let .channelPressure(value):
            .channelPressure(value: clamp(value, min: 0, max: 127))
        case let .polyPressure(note, value):
            .polyPressure(
                note: clamp(note, min: 0, max: 127),
                value: clamp(value, min: 0, max: 127)
            )
        }
    }

    private static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.max(min, Swift.min(max, value))
    }
}
