@testable import HappyPianistAVP
import Foundation
import Testing

@Test
func recordScrollPresentationEmphasizesTheCenteredRecord() {
    let center = LibraryRecordScrollPresentation(centerDistance: 0)
    let neighbor = LibraryRecordScrollPresentation(
        centerDistance: LibraryRecordLayout.diameter
    )
    let outerRecord = LibraryRecordScrollPresentation(
        centerDistance: LibraryRecordLayout.diameter * 2
    )

    #expect(center.scale == 1)
    #expect(center.opacity == 1)
    #expect(center.saturation == 1)
    #expect(center.scale > neighbor.scale)
    #expect(neighbor.scale > outerRecord.scale)
    #expect(center.opacity > neighbor.opacity)
    #expect(neighbor.opacity > outerRecord.opacity)
    #expect(center.saturation > neighbor.saturation)
    #expect(neighbor.saturation > outerRecord.saturation)
}

@Test
func settledUserScrollCommitsOnlyItsFinalDifferentTarget() {
    let selectedEntryID = UUID()
    let settledEntryID = UUID()

    #expect(
        LibraryRecordScrollSelectionDecision.selectionToCommit(
            scrollTargetID: settledEntryID,
            selectedEntryID: selectedEntryID
        ) == settledEntryID
    )
    #expect(
        LibraryRecordScrollSelectionDecision.selectionToCommit(
            scrollTargetID: settledEntryID,
            selectedEntryID: settledEntryID
        ) == nil
    )
}

@Test
func unchangedOrProgrammaticScrollTargetDoesNotCommitAgain() {
    let selectedEntryID = UUID()

    #expect(
        LibraryRecordScrollSelectionDecision.selectionToCommit(
            scrollTargetID: selectedEntryID,
            selectedEntryID: selectedEntryID
        ) == nil
    )
    #expect(
        LibraryRecordScrollSelectionDecision.selectionToCommit(
            scrollTargetID: nil,
            selectedEntryID: selectedEntryID
        ) == nil
    )
}

@Test
func centerTapTogglesPlaybackAndNeighborTapSelects() {
    let selectedEntryID = UUID()

    #expect(
        LibraryRecordScrollSelectionDecision.action(
            forTappedEntryID: selectedEntryID,
            selectedEntryID: selectedEntryID
        ) == .togglePlayback
    )
    #expect(
        LibraryRecordScrollSelectionDecision.action(
            forTappedEntryID: UUID(),
            selectedEntryID: selectedEntryID
        ) == .selectEntry
    )
}
