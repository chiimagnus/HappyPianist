import Foundation

struct MIDI1InputEvent: Equatable, Sendable {
    struct Source: Equatable, Hashable, Sendable {
        enum Identifier: Equatable, Hashable, Sendable {
            case endpointUniqueID(Int32)
            case sourceIndex(Int)
        }

        let identifier: Identifier
        let endpointName: String?
    }

    enum Kind: Equatable, Sendable {
        case noteOn(note: Int, velocity: Int)
        case noteOff(note: Int, velocity: Int)
        case controlChange(controller: Int, value: Int)
        case pitchBend(value: Int)
        case programChange(program: Int)
        case channelPressure(value: Int)
        case polyPressure(note: Int, value: Int)
    }

    let kind: Kind
    let channel: Int
    let group: Int
    let source: Source
    let receivedAt: Date
    let receivedAtUptimeSeconds: TimeInterval

    init(
        kind: Kind,
        channel: Int,
        group: Int,
        source: Source,
        receivedAt: Date,
        receivedAtUptimeSeconds: TimeInterval
    ) {
        self.kind = Self.clamp(kind)
        self.channel = Self.clamp(channel, min: 1, max: 16)
        self.group = Self.clamp(group, min: 0, max: 15)
        self.source = source
        self.receivedAt = receivedAt
        self.receivedAtUptimeSeconds = max(0, receivedAtUptimeSeconds)
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
