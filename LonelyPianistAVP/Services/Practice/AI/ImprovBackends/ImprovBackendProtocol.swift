import Foundation
import ImprovProtocol

protocol ImprovBackendProtocol: Sendable {
    var kind: ImprovBackendKind { get }
    var displayName: String { get }

    func generatePlaybackPlan(
        request: ImprovGenerateRequestV2,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan
}
