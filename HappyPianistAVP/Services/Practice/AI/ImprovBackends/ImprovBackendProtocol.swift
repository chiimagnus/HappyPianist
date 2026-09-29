import Foundation

protocol ImprovBackendProtocol: Sendable {
    var kind: ImprovBackendKind { get }
    var displayName: String { get }

    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration
    ) async throws -> CreativeDuetResponse
}
