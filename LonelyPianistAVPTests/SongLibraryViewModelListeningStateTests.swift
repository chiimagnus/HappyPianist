import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func listenButtonStateReflectsObservablePlaybackState() {
    let appModel = AppModel()
    let viewModel = SongLibraryViewModel(appModel: appModel)

    let entryID = UUID()
    viewModel.currentListeningEntryID = entryID
    viewModel.isCurrentListeningPlaying = true

    #expect(viewModel.isListeningPlaying(entryID: entryID))
    #expect(viewModel.isListeningPlaying(entryID: UUID()) == false)

    viewModel.isCurrentListeningPlaying = false
    #expect(viewModel.isListeningPlaying(entryID: entryID) == false)
}

