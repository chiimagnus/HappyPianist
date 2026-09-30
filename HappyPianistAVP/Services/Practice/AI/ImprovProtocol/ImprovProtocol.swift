import Foundation

public struct ImprovDialogueNote: Equatable, Sendable {
    public let note: Int
    public let velocity: Int
    public let time: Double
    public let duration: Double

    public init(note: Int, velocity: Int, time: Double, duration: Double) {
        self.note = note
        self.velocity = velocity
        self.time = time
        self.duration = duration
    }
}

public struct ImprovGenerateParams: Equatable, Sendable {
    public let topP: Double
    public let maxTokens: Int
    public let seed: UInt64

    public init(topP: Double, maxTokens: Int, seed: UInt64) {
        self.topP = topP
        self.maxTokens = maxTokens
        self.seed = seed
    }
}

public struct ImprovEvent: Codable, Equatable, Sendable {
    public enum EventType: String, Codable, Equatable, Sendable {
        case note
        case cc
    }

    public let type: EventType
    public let time: Double
    public let note: Int?
    public let velocity: Int?
    public let duration: Double?
    public let controller: Int?
    public let value: Int?

    public static func note(note: Int, velocity: Int, time: Double, duration: Double) -> Self {
        precondition(isValid7Bit(note), "MIDI note must be 0...127")
        precondition(isValid7Bit(velocity), "MIDI velocity must be 0...127")
        precondition(time.isFinite && time >= 0, "MIDI event time must be finite and non-negative")
        precondition(duration.isFinite && duration > 0, "MIDI note duration must be finite and positive")
        return Self(
            type: .note,
            time: time,
            note: note,
            velocity: velocity,
            duration: duration,
            controller: nil,
            value: nil
        )
    }

    public static func cc(controller: Int, value: Int, time: Double) -> Self {
        precondition(Self.allowedControllers.contains(controller), "Unsupported MIDI controller")
        precondition(isValid7Bit(value), "MIDI controller value must be 0...127")
        precondition(time.isFinite && time >= 0, "MIDI event time must be finite and non-negative")
        return Self(
            type: .cc,
            time: time,
            note: nil,
            velocity: nil,
            duration: nil,
            controller: controller,
            value: value
        )
    }

    private init(
        type: EventType,
        time: Double,
        note: Int?,
        velocity: Int?,
        duration: Double?,
        controller: Int?,
        value: Int?
    ) {
        self.type = type
        self.time = time
        self.note = note
        self.velocity = velocity
        self.duration = duration
        self.controller = controller
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let typeKey = AnyCodingKey("type")
        let rawType = try raw.decode(String.self, forKey: typeKey)
        guard let type = EventType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(
                forKey: typeKey,
                in: raw,
                debugDescription: "Unknown ImprovEvent type"
            )
        }

        let expectedKeys: Set<String> = switch type {
        case .note: ["type", "note", "velocity", "time", "duration"]
        case .cc: ["type", "controller", "value", "time"]
        }
        guard Set(raw.allKeys.map(\.stringValue)) == expectedKeys else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected ImprovEvent fields")
            )
        }

        let time = try raw.decode(Double.self, forKey: AnyCodingKey("time"))
        guard time.isFinite, time >= 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid ImprovEvent time")
            )
        }

        switch type {
        case .note:
            let note = try raw.decode(Int.self, forKey: AnyCodingKey("note"))
            let velocity = try raw.decode(Int.self, forKey: AnyCodingKey("velocity"))
            let duration = try raw.decode(Double.self, forKey: AnyCodingKey("duration"))
            guard Self.isValid7Bit(note), Self.isValid7Bit(velocity), duration.isFinite, duration > 0 else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid note event values")
                )
            }
            self.init(
                type: .note,
                time: time,
                note: note,
                velocity: velocity,
                duration: duration,
                controller: nil,
                value: nil
            )
        case .cc:
            let controller = try raw.decode(Int.self, forKey: AnyCodingKey("controller"))
            let value = try raw.decode(Int.self, forKey: AnyCodingKey("value"))
            guard Self.allowedControllers.contains(controller), Self.isValid7Bit(value) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid controller event values")
                )
            }
            self.init(
                type: .cc,
                time: time,
                note: nil,
                velocity: nil,
                duration: nil,
                controller: controller,
                value: value
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(type.rawValue, forKey: AnyCodingKey("type"))
        try container.encode(time, forKey: AnyCodingKey("time"))

        switch type {
        case .note:
            guard let note, let velocity, let duration,
                  Self.isValid7Bit(note), Self.isValid7Bit(velocity),
                  time.isFinite, time >= 0,
                  duration.isFinite, duration > 0
            else {
                throw EncodingError.invalidValue(
                    self,
                    .init(codingPath: encoder.codingPath, debugDescription: "Invalid note event invariant")
                )
            }
            try container.encode(note, forKey: AnyCodingKey("note"))
            try container.encode(velocity, forKey: AnyCodingKey("velocity"))
            try container.encode(duration, forKey: AnyCodingKey("duration"))
        case .cc:
            guard let controller, let value,
                  Self.allowedControllers.contains(controller), Self.isValid7Bit(value),
                  time.isFinite, time >= 0
            else {
                throw EncodingError.invalidValue(
                    self,
                    .init(codingPath: encoder.codingPath, debugDescription: "Invalid controller event invariant")
                )
            }
            try container.encode(controller, forKey: AnyCodingKey("controller"))
            try container.encode(value, forKey: AnyCodingKey("value"))
        }
    }

    private static let allowedControllers: Set<Int> = [7, 11, 64]

    private static func isValid7Bit(_ value: Int) -> Bool {
        (0 ... 127).contains(value)
    }
}

struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
