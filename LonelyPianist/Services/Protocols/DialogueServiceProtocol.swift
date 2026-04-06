import Foundation

enum DialogueServiceConnectionState: Equatable {
    case disconnected
    case connected
    case failed(String)
}

protocol DialogueServiceProtocol: AnyObject {
    var connectionState: DialogueServiceConnectionState { get }
    var onConnectionStateChange: (@Sendable (DialogueServiceConnectionState) -> Void)? { get set }

    func connect(url: URL)
    func disconnect()

    func generate(
        notes: [DialogueNote],
        params: DialogueGenerateParams,
        sessionID: String?
    ) async throws -> (notes: [DialogueNote], latencyMs: Int?)
}

