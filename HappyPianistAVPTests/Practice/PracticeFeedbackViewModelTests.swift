@testable import HappyPianistAVP
import Foundation
import Testing

@Test @MainActor
func feedbackViewModelReplacesAndCancelsCue() {
    let viewModel = PracticeFeedbackViewModel(sleeper: NeverFeedbackSleeper())
    let event = PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: nil,
        kind: .roundSummaryReady
    )
    viewModel.present(event)
    #expect(viewModel.cue == event)
    viewModel.cancel()
    #expect(viewModel.cue == nil)
}

@Test @MainActor
func scenePresentationInvalidationIsSynchronous() {
    let viewModel = ARGuideViewModel(
        appState: AppState(),
        practiceSetupState: PracticeSetupState()
    )
    let event = PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: nil,
        kind: .roundSummaryReady
    )
    viewModel.practiceFeedbackViewModel.present(event)
    viewModel.practiceSessionViewModel.latestFeedbackEvent = event

    viewModel.invalidatePracticeFeedbackPresentation()

    #expect(viewModel.practiceFeedbackViewModel.cue == nil)
    #expect(viewModel.practiceSessionViewModel.latestFeedbackEvent == nil)
}

private struct NeverFeedbackSleeper: SleeperProtocol {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
