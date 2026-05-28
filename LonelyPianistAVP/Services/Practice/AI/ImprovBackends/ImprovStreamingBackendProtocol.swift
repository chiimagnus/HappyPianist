import Foundation
import ImprovProtocol

protocol ImprovStreamingBackendProtocol: Sendable {
    func streamChunks(
        request: ImprovGenerateRequestV2,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<ImprovStreamChunkV2, Error>
}
