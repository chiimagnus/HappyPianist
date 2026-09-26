import Foundation

enum QwenClassifierClientError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodeFailed
    case unexpectedOutputTokens(Int)
}

struct QwenQuestion: Encodable, Equatable, Sendable {
    let type = "choice"
    let instructions: String
    let criteria: [String: String]

    static func choice(
        instructions: String,
        criteria: [String: String]
    ) -> Self {
        .init(instructions: instructions, criteria: criteria)
    }
}

struct QwenChoiceAnswer: Decodable, Equatable, Sendable {
    let choice: String
    let confidence: Double
    let probabilities: [String: Double]
}

enum QwenAnswer: Decodable, Equatable, Sendable {
    case choice(QwenChoiceAnswer)

    private enum Kind: String, Decodable {
        case choice
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .choice:
            self = .choice(try QwenChoiceAnswer(from: decoder))
        }
    }
}

struct QwenClassifierUsage: Decodable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct QwenClassifierResponse: Decodable, Equatable, Sendable {
    let model: String
    let answers: [String: QwenAnswer]
    let usage: QwenClassifierUsage
    let latencyMS: Int

    enum CodingKeys: String, CodingKey {
        case model
        case answers
        case usage
        case latencyMS = "latency_ms"
    }
}

private struct QwenClassifierRequest<State: Encodable>: Encodable {
    let model: String
    let state: State
    let questions: [String: QwenQuestion]
}

private struct QwenClassifierErrorResponse: Decodable {
    let message: String
}

protocol QwenClassifierClientProtocol: Sendable {
    func classify<State: Encodable & Sendable>(
        host: String,
        port: Int,
        model: String,
        state: State,
        questions: [String: QwenQuestion],
        timeoutSeconds: TimeInterval
    ) async throws -> QwenClassifierResponse
}

struct QwenClassifierClient: QwenClassifierClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func classify<State: Encodable & Sendable>(
        host: String,
        port: Int,
        model: String,
        state: State,
        questions: [String: QwenQuestion],
        timeoutSeconds: TimeInterval = 1.5
    ) async throws -> QwenClassifierResponse {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/v1/classifier"

        guard let url = components.url else {
            throw QwenClassifierClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(
            QwenClassifierRequest(
                model: model,
                state: state,
                questions: questions
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QwenClassifierClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = try? JSONDecoder().decode(
                QwenClassifierErrorResponse.self,
                from: data
            ).message
            throw QwenClassifierClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        guard let result = try? JSONDecoder().decode(
            QwenClassifierResponse.self,
            from: data
        ) else {
            throw QwenClassifierClientError.decodeFailed
        }
        guard result.usage.outputTokens == 0 else {
            throw QwenClassifierClientError.unexpectedOutputTokens(result.usage.outputTokens)
        }
        return result
    }
}
