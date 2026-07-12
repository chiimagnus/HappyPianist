@testable import HappyPianistAVP
import Foundation
import Testing

@Test @MainActor
func feedbackViewModelReplacesAndCancelsCue() {
    let viewModel = PracticeFeedbackViewModel(sleeper: NeverFeedbackSleeper())
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let event = PracticeFeedbackEvent(
        identity: identity,
        sessionGeneration: 1,
        roundGeneration: 1,
        sequence: 1,
        sourceMeasureID: nil,
        kind: .roundSummaryReady
    )
    viewModel.present(event)
    #expect(viewModel.cue == event)
    viewModel.cancel()
    #expect(viewModel.cue == nil)
}

private struct NeverFeedbackSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
