import Foundation

protocol ImprovBackendProtocol: Sendable {
    var kind: ImprovBackendKind { get }
    var displayName: String { get }

    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout: Duration
    ) async throws -> CreativeDuetResponse

    func generatePlaybackPlan(
        request: ImprovGenerateRequestV2,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan
}

extension ImprovBackendProtocol {
    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout: Duration
    ) async throws -> CreativeDuetResponse {
        let playbackPlan = try await generatePlaybackPlan(
            request: ImprovGenerateRequestV2(
                events: phrase.events,
                params: generation.parameters,
                sessionID: generation.sessionID
            ),
            timeout: timeout
        )

        switch playbackPlan {
        case let .schedule(schedule, backendLatencyMS):
            return CreativeDuetResponse(
                schedule: schedule,
                provider: kind,
                generation: generation,
                provenance: .backendGenerated(latencyMS: backendLatencyMS)
            )
        }
    }
}
