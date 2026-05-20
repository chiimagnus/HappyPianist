import Foundation
import ImprovProtocol

struct TickRangeReplayImprovBackend: ImprovBackendProtocol {
    let kind: ImprovBackendKind = .tickRangeReplay
    let displayName: String = "按谱片段回放"

    func generatePlaybackPlan(
        request _: ImprovGenerateRequest,
        timeout _: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        .tickRange(maxMeasures: 2)
    }
}
