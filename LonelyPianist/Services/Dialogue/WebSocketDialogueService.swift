import Foundation
import OSLog

enum WebSocketDialogueServiceError: LocalizedError {
    case notConnected
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Dialogue server is not connected"
        case .invalidResponse:
            return "Dialogue server returned an invalid response"
        case .serverError(let message):
            return message
        }
    }
}

@MainActor
final class WebSocketDialogueService: DialogueServiceProtocol {
    private struct GenerateRequest: Encodable {
        let type: String = "generate"
        let protocolVersion: Int = 1
        let notes: [DialogueNote]
        let params: DialogueGenerateParams
        let sessionID: String?

        enum CodingKeys: String, CodingKey {
            case type
            case protocolVersion = "protocol_version"
            case notes
            case params
            case sessionID = "session_id"
        }
    }

    private struct ServerEnvelope: Decodable {
        let type: String
        let protocolVersion: Int
        let notes: [DialogueNote]?
        let latencyMs: Int?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case type
            case protocolVersion = "protocol_version"
            case notes
            case latencyMs = "latency_ms"
            case message
        }
    }

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "DialogueWS")

    private(set) var connectionState: DialogueServiceConnectionState = .disconnected {
        didSet { onConnectionStateChange?(connectionState) }
    }

    var onConnectionStateChange: (@Sendable (DialogueServiceConnectionState) -> Void)?

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var url: URL?
    private var task: URLSessionWebSocketTask?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(url: URL) {
        guard self.url != url || task == nil else { return }
        disconnect()
        self.url = url

        let newTask = session.webSocketTask(with: url)
        task = newTask
        connectionState = .connected
        newTask.resume()
        logger.info("Dialogue WS connected: \(url.absoluteString, privacy: .public)")
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        url = nil
        connectionState = .disconnected
    }

    func generate(
        notes: [DialogueNote],
        params: DialogueGenerateParams,
        sessionID: String?
    ) async throws -> (notes: [DialogueNote], latencyMs: Int?) {
        guard let task else { throw WebSocketDialogueServiceError.notConnected }

        let request = GenerateRequest(notes: notes, params: params, sessionID: sessionID)
        let data = try encoder.encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw WebSocketDialogueServiceError.invalidResponse
        }

        try await task.send(.string(json))

        let message = try await task.receive()
        let payload: Data
        switch message {
        case .data(let data):
            payload = data
        case .string(let string):
            guard let data = string.data(using: .utf8) else {
                throw WebSocketDialogueServiceError.invalidResponse
            }
            payload = data
        @unknown default:
            throw WebSocketDialogueServiceError.invalidResponse
        }

        let envelope = try decoder.decode(ServerEnvelope.self, from: payload)

        switch envelope.type {
        case "result":
            return (envelope.notes ?? [], envelope.latencyMs)
        case "error":
            throw WebSocketDialogueServiceError.serverError(envelope.message ?? "Unknown server error")
        default:
            throw WebSocketDialogueServiceError.invalidResponse
        }
    }
}
