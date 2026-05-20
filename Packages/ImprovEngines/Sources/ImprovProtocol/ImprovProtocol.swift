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

public struct ImprovGenerateRequest: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var notes: [ImprovDialogueNote]
    public var params: ImprovGenerateParams
    public var sessionID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case notes
        case params
        case sessionID = "session_id"
    }

    public init(
        protocolVersion: Int = 1,
        notes: [ImprovDialogueNote],
        params: ImprovGenerateParams,
        sessionID: String? = nil
    ) {
        type = "generate"
        self.protocolVersion = protocolVersion
        self.notes = notes
        self.params = params
        self.sessionID = sessionID
    }
}

public struct ImprovResultResponse: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var notes: [ImprovDialogueNote]
    public var latencyMS: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case notes
        case latencyMS = "latency_ms"
    }

    public init(type: String, protocolVersion: Int, notes: [ImprovDialogueNote], latencyMS: Int? = nil) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.notes = notes
        self.latencyMS = latencyMS
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

