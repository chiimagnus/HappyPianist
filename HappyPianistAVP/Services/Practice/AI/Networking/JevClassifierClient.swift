import Foundation

enum JevClassifierClientError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodeFailed
    case unexpectedOutputTokens(Int)
}

struct JevQuestion: Codable, Equatable, Sendable {
    let type: String
    let instructions: String
    let criteria: [String: String?]

    static func choice(
        instructions: String,
        criteria: [String: String?]
    ) -> Self {
        .init(
            type: "choice",
            instructions: instructions,
            criteria: criteria
        )
    }

    static func noul(
        instructions: String,
        trueDescription: String? = nil,
        falseDescription: String? = nil
    ) -> Self {
        var criteria: [String: String?] = [:]
        if let trueDescription {
            criteria["true"] = trueDescription
        }
        if let falseDescription {
            criteria["false"] = falseDescription
        }
        return .init(
            type: "noul",
            instructions: instructions,
            criteria: criteria
        )
    }
}

struct JevChoiceAnswer: Decodable, Equatable, Sendable {
    let choice: String
    let confidence: Double
    let probabilities: [String: Double]
}

struct JevNoulRating: Decodable, Equatable, Sendable {
    let expectedScore: Double
    let probabilities: [String: Double]

    enum CodingKeys: String, CodingKey {
        case expectedScore = "expected_score"
        case probabilities
    }
}

struct JevNoulAnswer: Decodable, Equatable, Sendable {
    let noul: Double
    let calibrated: Bool
    let rating: JevNoulRating
}

enum JevAnswer: Decodable, Equatable, Sendable {
    case choice(JevChoiceAnswer)
    case noul(JevNoulAnswer)

    private enum Kind: String, Decodable {
        case choice
        case noul
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .choice:
            self = .choice(try JevChoiceAnswer(from: decoder))
        case .noul:
            self = .noul(try JevNoulAnswer(from: decoder))
        }
    }
}

struct JevClassifierUsage: Decodable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct JevClassifierResponse: Decodable, Equatable, Sendable {
    let model: String
    let answers: [String: JevAnswer]
    let usage: JevClassifierUsage
    let latencyMS: Int

    enum CodingKeys: String, CodingKey {
        case model
        case answers
        case usage
        case latencyMS = "latency_ms"
    }
}

private struct JevClassifierRequest: Codable {
    let model: String
    let state: String
    let questions: [String: JevQuestion]
}

private struct JevClassifierErrorResponse: Codable {
    let message: String
}

protocol JevClassifierClientProtocol: Sendable {
    func classify(
        host: String,
        port: Int,
        model: String,
        state: String,
        questions: [String: JevQuestion],
        timeoutSeconds: TimeInterval
    ) async throws -> JevClassifierResponse
}

struct JevClassifierClient: JevClassifierClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func classify(
        host: String,
        port: Int,
        model: String,
        state: String,
        questions: [String: JevQuestion],
        timeoutSeconds: TimeInterval = 1
    ) async throws -> JevClassifierResponse {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/v1/classifier"

        guard let url = components.url else {
            throw JevClassifierClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            JevClassifierRequest(
                model: model,
                state: state,
                questions: questions
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JevClassifierClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = try? JSONDecoder().decode(
                JevClassifierErrorResponse.self,
                from: data
            ).message
            throw JevClassifierClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        guard let result = try? JSONDecoder().decode(
            JevClassifierResponse.self,
            from: data
        ) else {
            throw JevClassifierClientError.decodeFailed
        }
        guard result.usage.outputTokens == 0 else {
            throw JevClassifierClientError.unexpectedOutputTokens(result.usage.outputTokens)
        }
        return result
    }
}
