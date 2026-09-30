import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func settledUserScrollCommitsOnlyItsFinalDifferentTarget() {
    let selectedEntryID = UUID()
    let settledEntryID = UUID()

    #expect(
        LibraryBookFlowSelectionDecision.selectionToCommit(
            scrollTargetID: settledEntryID,
            selectedEntryID: selectedEntryID
        ) == settledEntryID
    )
    #expect(
        LibraryBookFlowSelectionDecision.selectionToCommit(
            scrollTargetID: settledEntryID,
            selectedEntryID: settledEntryID
        ) == nil
    )
}

@Test
func unchangedOrProgrammaticScrollTargetDoesNotCommitAgain() {
    let selectedEntryID = UUID()

    #expect(
        LibraryBookFlowSelectionDecision.selectionToCommit(
            scrollTargetID: selectedEntryID,
            selectedEntryID: selectedEntryID
        ) == nil
    )
    #expect(
        LibraryBookFlowSelectionDecision.selectionToCommit(
            scrollTargetID: nil,
            selectedEntryID: selectedEntryID
        ) == nil
    )
}

@Test
func centerTapTogglesPlaybackAndNeighborTapSelects() {
    let selectedEntryID = UUID()

    #expect(
        LibraryBookFlowSelectionDecision.action(
            forTappedEntryID: selectedEntryID,
            selectedEntryID: selectedEntryID
        ) == .togglePlayback
    )
    #expect(
        LibraryBookFlowSelectionDecision.action(
            forTappedEntryID: UUID(),
            selectedEntryID: selectedEntryID
        ) == .selectEntry
    )
}
