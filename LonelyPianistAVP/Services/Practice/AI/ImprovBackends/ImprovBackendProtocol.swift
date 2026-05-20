import Foundation
import ImprovProtocol

protocol ImprovBackendProtocol: Sendable {
    var kind: ImprovBackendKind { get }
    var displayName: String { get }

    func generatePlaybackPlan(
        request: ImprovGenerateRequest,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan
}
