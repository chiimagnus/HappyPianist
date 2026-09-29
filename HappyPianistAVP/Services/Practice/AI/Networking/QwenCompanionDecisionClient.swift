import Foundation

enum QwenCompanionDecisionClientError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, code: String, message: String?)
    case decodeFailed
    case unexpectedModel(String)
    case unexpectedOutputTokens(Int)
    case invalidSemanticValues
    case invalidUsage
}

struct QwenCompanionState: Encodable, Equatable, Sendable {
    let heldNotesCount: Int
    let sustainValue: Int
    let recentIOIMedianSeconds: TimeInterval?
    let recentNoteDensityPerSecond: Double
    let secondsSinceLastNoteOn: TimeInterval?
    let isAIPlaybackActive: Bool
    let userNoteOnSinceAIPlaybackStarted: Bool

    enum CodingKeys: String, CodingKey {
        case heldNotesCount = "held_notes_count"
        case sustainValue = "sustain_value"
        case recentIOIMedianSeconds = "recent_ioi_median_seconds"
        case recentNoteDensityPerSecond = "recent_note_density_per_second"
        case secondsSinceLastNoteOn = "seconds_since_last_note_on"
        case isAIPlaybackActive = "is_ai_playback_active"
        case userNoteOnSinceAIPlaybackStarted = "user_note_on_since_ai_playback_started"
    }
}

enum QwenCompanionAction: String, Decodable, Equatable, Sendable {
    case listen
    case support
    case sparse
    case yield
    case respond
}

struct QwenSemanticValues: Decodable, Equatable, Sendable {
    let continuing: Double
    let finished: Double
    let space: Double
    let reasserted: Double

    var allValues: [Double] {
        [continuing, finished, space, reasserted]
    }
}

struct QwenCompanionUsage: Decodable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct QwenCompanionDecisionResponse: Decodable, Equatable, Sendable {
    let model: String
    let action: QwenCompanionAction
    let semanticScores: QwenSemanticValues
    let semanticOrderGaps: QwenSemanticValues
    let usage: QwenCompanionUsage
    let serverLatencyMS: Int

    enum CodingKeys: String, CodingKey {
        case model
        case action
        case semanticScores = "semantic_scores"
        case semanticOrderGaps = "semantic_order_gaps"
        case usage
        case serverLatencyMS = "server_latency_ms"
    }
}

private struct QwenCompanionDecisionRequest: Encodable {
    let state: QwenCompanionState
}

private struct QwenCompanionErrorResponse: Decodable {
    let code: String
    let message: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actualKeys = Set(container.allKeys)
        guard actualKeys.contains(.code), actualKeys.isSubset(of: Set(CodingKeys.allCases)) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected Qwen error fields")
            )
        }
        code = try container.decode(String.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        guard code.isEmpty == false else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: container,
                debugDescription: "Qwen error code must be non-empty"
            )
        }
    }
}

protocol QwenCompanionDecisionClientProtocol: Sendable {
    func decide(
        host: String,
        port: Int,
        state: QwenCompanionState,
        timeoutSeconds: TimeInterval
    ) async throws -> QwenCompanionDecisionResponse
}

struct QwenCompanionDecisionClient: QwenCompanionDecisionClientProtocol {
    static let expectedModel = "Qwen/Qwen3.5-0.8B"
    static let path = "/v1/companion-decision"

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func decide(
        host: String,
        port: Int,
        state: QwenCompanionState,
        timeoutSeconds: TimeInterval
    ) async throws -> QwenCompanionDecisionResponse {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = Self.path

        guard let url = components.url else {
            throw QwenCompanionDecisionClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(QwenCompanionDecisionRequest(state: state))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QwenCompanionDecisionClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            guard let errorResponse = try? JSONDecoder().decode(QwenCompanionErrorResponse.self, from: data) else {
                throw QwenCompanionDecisionClientError.decodeFailed
            }
            throw QwenCompanionDecisionClientError.httpError(
                statusCode: httpResponse.statusCode,
                code: errorResponse.code,
                message: errorResponse.message
            )
        }

        guard Self.hasExactResponseShape(data) else {
            throw QwenCompanionDecisionClientError.decodeFailed
        }
        guard let result = try? JSONDecoder().decode(QwenCompanionDecisionResponse.self, from: data) else {
            throw QwenCompanionDecisionClientError.decodeFailed
        }
        guard result.model == Self.expectedModel else {
            throw QwenCompanionDecisionClientError.unexpectedModel(result.model)
        }
        guard result.usage.inputTokens >= 0, result.serverLatencyMS >= 0 else {
            throw QwenCompanionDecisionClientError.invalidUsage
        }
        guard result.usage.outputTokens == 0 else {
            throw QwenCompanionDecisionClientError.unexpectedOutputTokens(result.usage.outputTokens)
        }
        let semanticValues = result.semanticScores.allValues + result.semanticOrderGaps.allValues
        guard semanticValues.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
            throw QwenCompanionDecisionClientError.invalidSemanticValues
        }
        return result
    }

    private static func hasExactResponseShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set([
                  "model",
                  "action",
                  "semantic_scores",
                  "semantic_order_gaps",
                  "usage",
                  "server_latency_ms",
              ]),
              let semanticScores = root["semantic_scores"] as? [String: Any],
              let semanticOrderGaps = root["semantic_order_gaps"] as? [String: Any],
              let usage = root["usage"] as? [String: Any]
        else {
            return false
        }

        let semanticKeys = Set(["continuing", "finished", "space", "reasserted"])
        return Set(semanticScores.keys) == semanticKeys
            && Set(semanticOrderGaps.keys) == semanticKeys
            && Set(usage.keys) == Set(["input_tokens", "output_tokens"])
    }
}
