import Foundation

enum CompanionDecisionClientError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodeFailed
}

private struct CompanionDecisionRequestV1: Codable {
    let protocolVersion = 1
    let input: CompanionDecisionInput
}

struct CompanionDecisionResponseV1: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let action: CompanionAction
    let confidence: Double
    let probabilities: [String: Double]
    let latencyMS: Int
    let model: String

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case action
        case confidence
        case probabilities
        case latencyMS = "latency_ms"
        case model
    }
}

private struct CompanionDecisionErrorResponseV1: Codable {
    let protocolVersion: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case message
    }
}

protocol CompanionDecisionClientProtocol: Sendable {
    func decide(
        host: String,
        port: Int,
        input: CompanionDecisionInput,
        timeoutSeconds: TimeInterval
    ) async throws -> CompanionDecisionResponseV1
}

struct CompanionDecisionClient: CompanionDecisionClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func decide(
        host: String,
        port: Int,
        input: CompanionDecisionInput,
        timeoutSeconds: TimeInterval = 1
    ) async throws -> CompanionDecisionResponseV1 {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/decision"

        guard let url = components.url else {
            throw CompanionDecisionClientError.invalidURL
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            CompanionDecisionRequestV1(input: input)
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionDecisionClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = try? decoder.decode(
                CompanionDecisionErrorResponseV1.self,
                from: data
            ).message
            throw CompanionDecisionClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        guard let result = try? decoder.decode(
            CompanionDecisionResponseV1.self,
            from: data
        ) else {
            throw CompanionDecisionClientError.decodeFailed
        }
        return result
    }
}
