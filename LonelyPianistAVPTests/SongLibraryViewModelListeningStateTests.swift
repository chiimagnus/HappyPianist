import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func listenButtonStateReflectsObservablePlaybackState() {
    let appState = AppState()
    let viewModel = SongLibraryViewModel(appState: appState)

    let entryID = UUID()
    viewModel.currentListeningEntryID = entryID
    viewModel.isCurrentListeningPlaying = true

    #expect(viewModel.isListeningPlaying(entryID: entryID))
    #expect(viewModel.isListeningPlaying(entryID: UUID()) == false)

    viewModel.isCurrentListeningPlaying = false
    #expect(viewModel.isListeningPlaying(entryID: entryID) == false)
}
