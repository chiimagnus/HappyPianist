import Foundation

enum AriaNetworkProtocol {
    static let version = 3
    static let path = "/generate"
}

struct AriaGenerateParams: Codable, Equatable, Sendable {
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case maxTokens = "max_tokens"
    }

    init(maxTokens: Int) {
        precondition((1 ... 8192).contains(maxTokens), "maxTokens must be 1...8192")
        self.maxTokens = maxTokens
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == Set(["max_tokens"]) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected Aria params fields")
            )
        }
        let maxTokens = try raw.decode(Int.self, forKey: AnyCodingKey("max_tokens"))
        guard (1 ... 8192).contains(maxTokens) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "max_tokens must be 1...8192")
            )
        }
        self.maxTokens = maxTokens
    }
}

struct AriaGenerateRequest: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let events: [ImprovEvent]
    let params: AriaGenerateParams

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case events
        case params
    }

    init(events: [ImprovEvent], maxTokens: Int) {
        precondition(
            events.allSatisfy { event in
                event.type != .cc || event.controller == 64
            },
            "Aria prompt only accepts observed sustain CC64"
        )
        type = "generate"
        protocolVersion = AriaNetworkProtocol.version
        self.events = events
        params = AriaGenerateParams(maxTokens: maxTokens)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected Aria request fields")
            )
        }
        type = try container.decode(String.self, forKey: .type)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        guard type == "generate", protocolVersion == AriaNetworkProtocol.version else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Aria request envelope")
            )
        }
        events = try container.decode([ImprovEvent].self, forKey: .events)
        guard events.allSatisfy({ $0.type != .cc || $0.controller == 64 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .events,
                in: container,
                debugDescription: "Aria prompt only accepts observed sustain CC64"
            )
        }
        params = try container.decode(AriaGenerateParams.self, forKey: .params)
    }
}

struct AriaResultResponse: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let events: [ImprovEvent]
    let latencyMS: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case protocolVersion = "protocol_version"
        case events
        case latencyMS = "latency_ms"
    }

    init(events: [ImprovEvent], latencyMS: Int) {
        precondition(latencyMS >= 0, "latencyMS must be non-negative")
        type = "result"
        protocolVersion = AriaNetworkProtocol.version
        self.events = events
        self.latencyMS = latencyMS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected Aria result fields")
            )
        }
        type = try container.decode(String.self, forKey: .type)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        guard type == "result", protocolVersion == AriaNetworkProtocol.version else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Aria result envelope")
            )
        }
        events = try container.decode([ImprovEvent].self, forKey: .events)
        latencyMS = try container.decode(Int.self, forKey: .latencyMS)
        guard latencyMS >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .latencyMS,
                in: container,
                debugDescription: "latency_ms must be non-negative"
            )
        }
    }
}

struct AriaErrorResponse: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let code: String
    let message: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case protocolVersion = "protocol_version"
        case code
        case message
    }

    init(code: String, message: String? = nil) {
        type = "error"
        protocolVersion = AriaNetworkProtocol.version
        self.code = code
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actualKeys = Set(container.allKeys)
        let requiredKeys: Set<CodingKeys> = [.type, .protocolVersion, .code]
        guard requiredKeys.isSubset(of: actualKeys), actualKeys.isSubset(of: Set(CodingKeys.allCases)) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected Aria error fields")
            )
        }
        type = try container.decode(String.self, forKey: .type)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        guard type == "error", protocolVersion == AriaNetworkProtocol.version, code.isEmpty == false else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Aria error envelope")
            )
        }
    }
}

private extension AriaGenerateRequest.CodingKeys {
    static let allCases: [Self] = [.type, .protocolVersion, .events, .params]
}
