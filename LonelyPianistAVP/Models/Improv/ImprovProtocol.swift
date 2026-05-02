import Foundation

struct ImprovDialogueNote: Codable, Equatable {
    var note: Int
    var velocity: Int
    var time: Double
    var duration: Double
}

struct ImprovGenerateParams: Codable, Equatable {
    var topP: Double
    var maxTokens: Int
    var strategy: String

    enum CodingKeys: String, CodingKey {
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case strategy
    }
}

struct ImprovGenerateRequest: Codable, Equatable {
    var type: String
    var protocolVersion: Int
    var notes: [ImprovDialogueNote]
    var params: ImprovGenerateParams
    var sessionID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case notes
        case params
        case sessionID = "session_id"
    }

    init(
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

struct ImprovResultResponse: Codable, Equatable {
    var type: String
    var protocolVersion: Int
    var notes: [ImprovDialogueNote]
    var latencyMS: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case notes
        case latencyMS = "latency_ms"
    }
}

struct ImprovErrorResponse: Codable, Equatable {
    var type: String
    var protocolVersion: Int
    var message: String

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case message
    }
}

