import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func listenButtonStateReflectsObservablePlaybackState() {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = SongLibraryViewModelTestHarness.make(appState: appState, practiceSetupState: practiceSetupState)

    let entryID = UUID()
    viewModel.currentListeningEntryID = entryID
    viewModel.isCurrentListeningPlaying = true

    #expect(viewModel.isListeningPlaying(entryID: entryID))
    #expect(viewModel.isListeningPlaying(entryID: UUID()) == false)

    viewModel.isCurrentListeningPlaying = false
    #expect(viewModel.isListeningPlaying(entryID: entryID) == false)
}
