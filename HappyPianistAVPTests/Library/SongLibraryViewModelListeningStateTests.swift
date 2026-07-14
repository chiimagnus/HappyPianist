import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func listenButtonStateReflectsObservablePlaybackState() {
    let viewModel = SongLibraryViewModelTestHarness.make()

    let entryID = UUID()
    viewModel.currentListeningEntryID = entryID
    viewModel.isCurrentListeningPlaying = true

    #expect(viewModel.isListeningPlaying(entryID: entryID))
    #expect(viewModel.isListeningPlaying(entryID: UUID()) == false)

    viewModel.isCurrentListeningPlaying = false
    #expect(viewModel.isListeningPlaying(entryID: entryID) == false)
}
