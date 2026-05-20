import Foundation

struct MIDI2InputEvent: Equatable, Sendable {
    struct Source: Equatable, Hashable, Sendable {
        enum Identifier: Equatable, Hashable, Sendable {
            case endpointUniqueID(Int32)
            case sourceIndex(Int)
        }

        let identifier: Identifier
        let endpointName: String?
    }

    enum Kind: Equatable, Sendable {
        case noteOn(note: Int, velocity16: UInt16)
        case noteOff(note: Int, velocity16: UInt16)
        case controlChange(controller: Int, value32: UInt32)
        case pitchBend(value32: UInt32)
        case programChange(program: Int)
        case channelPressure(value32: UInt32)
        case polyPressure(note: Int, pressure32: UInt32)
    }

    let kind: Kind
    let channel: Int
    let group: Int
    let source: Source
    let receivedAt: Date
    let receivedAtUptimeSeconds: TimeInterval
    let debugEventID: Int64?

    init(
        kind: Kind,
        channel: Int,
        group: Int,
        source: Source,
        receivedAt: Date,
        receivedAtUptimeSeconds: TimeInterval,
        debugEventID: Int64? = nil
    ) {
        self.kind = Self.clamp(kind)
        self.channel = Self.clamp(channel, min: 1, max: 16)
        self.group = Self.clamp(group, min: 0, max: 15)
        self.source = source
        self.receivedAt = receivedAt
        self.receivedAtUptimeSeconds = max(0, receivedAtUptimeSeconds)
        self.debugEventID = debugEventID
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
