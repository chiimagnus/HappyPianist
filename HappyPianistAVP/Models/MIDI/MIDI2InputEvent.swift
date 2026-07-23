import Foundation

struct MIDI2InputEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case noteOn(note: Int, velocity16: UInt16)
        case noteOff(note: Int, velocity16: UInt16)
        case controlChange(controller: Int, value32: UInt32)
        case pitchBend(value32: UInt32)
        case programChange(program: Int)
        case channelPressure(value32: UInt32)
        case polyPressure(note: Int, pressure32: UInt32)
    }

    /// Stable while the same raw input event is routed to matching, recording, and AI.
    let observationID: UUID
    let kind: Kind
    let channel: Int
    let group: Int
    let source: MIDIInputSource
    let receivedAt: Date
    let receivedAtUptimeSeconds: TimeInterval
    let sourceTimestamp: PerformanceSourceTimestamp?

    init(
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
