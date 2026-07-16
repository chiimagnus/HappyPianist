import Foundation

public struct ImprovDialogueNote: Codable, Equatable, Sendable {
    public var note: Int
    public var velocity: Int
    public var time: Double
    public var duration: Double

    public init(note: Int, velocity: Int, time: Double, duration: Double) {
        self.note = note
        self.velocity = velocity
        self.time = time
        self.duration = duration
    }
}

public struct ImprovGenerateParams: Codable, Equatable, Sendable {
    public var topP: Double
    public var maxTokens: Int
    public var strategy: String
    public var seed: UInt64?

    public init(topP: Double, maxTokens: Int, strategy: String, seed: UInt64? = nil) {
        self.topP = topP
        self.maxTokens = maxTokens
        self.strategy = strategy
        self.seed = seed
    }

    enum CodingKeys: String, CodingKey {
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case strategy
        case seed
    }
}

public struct ImprovErrorResponse: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var message: String

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case message
    }

    public init(type: String, protocolVersion: Int, message: String) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.message = message
    }
}

// MARK: - v2 (events-first)

public struct ImprovEvent: Codable, Equatable, Sendable {
    public enum EventType: String, Codable, Equatable, Sendable {
        case note
        case cc
    }

    public var type: EventType
    public var time: Double

    public var note: Int?
    public var velocity: Int?
    public var duration: Double?

    public var controller: Int?
    public var value: Int?

    public static func note(note: Int, velocity: Int, time: Double, duration: Double) -> ImprovEvent {
        ImprovEvent(
            type: .note,
            time: sanitizeSeconds(time),
            note: clamp7Bit(note),
            velocity: clamp7Bit(velocity),
            duration: sanitizeSeconds(duration),
            controller: nil,
            value: nil
        )
    }

    public static func cc(controller: Int, value: Int, time: Double) -> ImprovEvent {
        ImprovEvent(
            type: .cc,
            time: sanitizeSeconds(time),
            note: nil,
            velocity: nil,
            duration: nil,
            controller: clamp7Bit(controller),
            value: clamp7Bit(value)
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case note
        case velocity
        case time
        case duration
        case controller
        case value
    }

    public init(
        type: EventType,
        time: Double,
        note: Int? = nil,
        velocity: Int? = nil,
        duration: Double? = nil,
        controller: Int? = nil,
        value: Int? = nil
    ) {
        self.type = type
        self.time = Self.sanitizeSeconds(time)
        self.note = note.map(Self.clamp7Bit)
        self.velocity = velocity.map(Self.clamp7Bit)
        self.duration = duration.map(Self.sanitizeSeconds)
        self.controller = controller.map(Self.clamp7Bit)
        self.value = value.map(Self.clamp7Bit)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(EventType.self, forKey: .type)
        time = try Self.sanitizeSeconds(container.decode(Double.self, forKey: .time))

        switch type {
        case .note:
            let rawNote = try container.decode(Int.self, forKey: .note)
            let rawVelocity = try container.decode(Int.self, forKey: .velocity)
            let rawDuration = try container.decode(Double.self, forKey: .duration)

            note = Self.clamp7Bit(rawNote)
            velocity = Self.clamp7Bit(rawVelocity)
            duration = Self.sanitizeSeconds(rawDuration)
            controller = nil
            value = nil
        case .cc:
            let rawController = try container.decode(Int.self, forKey: .controller)
            let rawValue = try container.decode(Int.self, forKey: .value)

            note = nil
            velocity = nil
            duration = nil
            controller = Self.clamp7Bit(rawController)
            value = Self.clamp7Bit(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(time, forKey: .time)

        switch type {
        case .note:
            guard let note, let velocity, let duration else {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "ImprovEvent.note requires note/velocity/duration."
                    )
                )
            }
            try container.encode(Self.clamp7Bit(note), forKey: .note)
            try container.encode(Self.clamp7Bit(velocity), forKey: .velocity)
            try container.encode(Self.sanitizeSeconds(duration), forKey: .duration)
        case .cc:
            guard let controller, let value else {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "ImprovEvent.cc requires controller/value."
                    )
                )
            }
            try container.encode(Self.clamp7Bit(controller), forKey: .controller)
            try container.encode(Self.clamp7Bit(value), forKey: .value)
        }
    }

    private static func sanitizeSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    private static func clamp7Bit(_ value: Int) -> Int {
        min(127, max(0, value))
    }
}

public struct ImprovGenerateRequestV2: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var events: [ImprovEvent]
    public var params: ImprovGenerateParams
    public var sessionID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case events
        case params
        case sessionID = "session_id"
    }

    public init(
        protocolVersion: Int = 2,
        events: [ImprovEvent],
        params: ImprovGenerateParams,
        sessionID: String? = nil
    ) {
        type = "generate"
        self.protocolVersion = protocolVersion
        self.events = events
        self.params = params
        self.sessionID = sessionID
    }
}

public struct ImprovResultResponseV2: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var events: [ImprovEvent]
    public var latencyMS: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case events
        case latencyMS = "latency_ms"
    }

    public init(type: String, protocolVersion: Int, events: [ImprovEvent], latencyMS: Int? = nil) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.events = events
        self.latencyMS = latencyMS
    }
}

public extension ImprovGenerateRequestV2 {
    func extractDialogueNotes() -> [ImprovDialogueNote] {
        events.compactMap { event in
            guard event.type == .note else { return nil }
            guard let note = event.note, let velocity = event.velocity, let duration = event.duration else { return nil }
            return ImprovDialogueNote(note: note, velocity: velocity, time: event.time, duration: duration)
        }
        .sorted { $0.time < $1.time }
    }
}
