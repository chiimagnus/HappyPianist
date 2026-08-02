import Foundation

public struct MIDI2InputEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case noteOn(note: Int, velocity16: UInt16)
        case noteOff(note: Int, velocity16: UInt16)
        case controlChange(controller: Int, value32: UInt32)
        case pitchBend(value32: UInt32)
        case programChange(program: Int)
        case channelPressure(value32: UInt32)
        case polyPressure(note: Int, pressure32: UInt32)
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
        case let .noteOn(note, velocity16):
            .noteOn(
                note: clamp(note, min: 0, max: 127),
                velocity16: velocity16
            )
        case let .noteOff(note, velocity16):
            .noteOff(
                note: clamp(note, min: 0, max: 127),
                velocity16: velocity16
            )
        case let .controlChange(controller, value32):
            .controlChange(
                controller: clamp(controller, min: 0, max: 127),
                value32: value32
            )
        case let .pitchBend(value32):
            .pitchBend(value32: value32)
        case let .programChange(program):
            .programChange(program: clamp(program, min: 0, max: 127))
        case let .channelPressure(value32):
            .channelPressure(value32: value32)
        case let .polyPressure(note, pressure32):
            .polyPressure(
                note: clamp(note, min: 0, max: 127),
                pressure32: pressure32
            )
        }
    }

    private static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.max(min, Swift.min(max, value))
    }
}
