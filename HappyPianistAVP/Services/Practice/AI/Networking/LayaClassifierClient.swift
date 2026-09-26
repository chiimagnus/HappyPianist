import Foundation

enum LayaClassifierClientError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodeFailed
    case unexpectedOutputTokens(Int)
}

enum LayaQuestion: Encodable, Equatable, Sendable {
    case choice(instructions: String, criteria: [String: String?])
    case score(instructions: String, criteria: [String])
    case noul(
        instructions: String,
        trueDescription: String? = nil,
        falseDescription: String? = nil
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case instructions
        case criteria
    }

    private enum Kind: String, Encodable {
        case choice
        case score
        case noul
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .choice(instructions, criteria):
            try container.encode(Kind.choice, forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case let .score(instructions, criteria):
            try container.encode(Kind.score, forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case let .noul(instructions, trueDescription, falseDescription):
            try container.encode(Kind.noul, forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            var criteria: [String: String?] = [:]
            if let trueDescription {
                criteria["true"] = trueDescription
            }
            if let falseDescription {
                criteria["false"] = falseDescription
            }
            try container.encode(criteria, forKey: .criteria)
        }
    }
}

struct LayaActionTrace: Decodable, Equatable, Sendable {
    let actProbability: Double

    enum CodingKeys: String, CodingKey {
        case actProbability = "act_probability"
    }
}

struct LayaChoiceAnswer: Decodable, Equatable, Sendable {
    let choice: String
    let confidence: Double
    let action: LayaActionTrace
    let probabilities: [String: Double]
}

struct LayaScoreAnswer: Decodable, Equatable, Sendable {
    let score: Double
    let confidence: Double
    let action: LayaActionTrace
    let legend: [String: String]
    let probabilities: [String: Double]
}

struct LayaNoulAnswer: Decodable, Equatable, Sendable {
    let noul: Double
    let confidence: Double
    let action: LayaActionTrace
}

enum LayaAnswer: Decodable, Equatable, Sendable {
    case choice(LayaChoiceAnswer)
    case score(LayaScoreAnswer)
    case noul(LayaNoulAnswer)

    private enum Kind: String, Decodable {
        case choice
        case score
        case noul
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .choice:
            self = .choice(try LayaChoiceAnswer(from: decoder))
        case .score:
            self = .score(try LayaScoreAnswer(from: decoder))
        case .noul:
            self = .noul(try LayaNoulAnswer(from: decoder))
        }
    }
}

struct LayaClassifierUsage: Decodable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct LayaClassifierResponse: Decodable, Equatable, Sendable {
    let model: String
    let answers: [String: LayaAnswer]
    let usage: LayaClassifierUsage
    let latencyMS: Int

    enum CodingKeys: String, CodingKey {
        case model
        case answers
        case usage
        case latencyMS = "latency_ms"
    }
}

private struct LayaClassifierRequest<State: Encodable>: Encodable {
    let model: String
    let state: State
    let questions: [String: LayaQuestion]
}

private struct LayaClassifierErrorResponse: Decodable {
    let message: String
}

protocol LayaClassifierClientProtocol: Sendable {
    func classify<State: Encodable & Sendable>(
        host: String,
        port: Int,
        model: String,
        state: State,
        questions: [String: LayaQuestion],
        timeoutSeconds: TimeInterval
    ) async throws -> LayaClassifierResponse
}

struct LayaClassifierClient: LayaClassifierClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func classify<State: Encodable & Sendable>(
        host: String,
        port: Int,
        model: String,
        state: State,
        questions: [String: LayaQuestion],
        timeoutSeconds: TimeInterval = 1
    ) async throws -> LayaClassifierResponse {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/v1/classifier"

        guard let url = components.url else {
            throw LayaClassifierClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(
            LayaClassifierRequest(
                model: model,
                state: state,
                questions: questions
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LayaClassifierClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = try? JSONDecoder().decode(
                LayaClassifierErrorResponse.self,
                from: data
            ).message
            throw LayaClassifierClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        guard let result = try? JSONDecoder().decode(
            LayaClassifierResponse.self,
            from: data
        ) else {
            throw LayaClassifierClientError.decodeFailed
        }
        guard result.usage.outputTokens == 0 else {
            throw LayaClassifierClientError.unexpectedOutputTokens(result.usage.outputTokens)
        }
        return result
    }
}
