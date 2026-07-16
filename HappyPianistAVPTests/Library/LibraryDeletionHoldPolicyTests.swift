@testable import HappyPianistAVP
import Foundation
import Testing

@Test
func deletionHoldRequiresThresholdAndAnEligibleEntry() {
    #expect(LibraryDeletionHoldPolicy.progress(for: -1) == 0)
    #expect(LibraryDeletionHoldPolicy.progress(for: LibraryDesignTokens.liftMaximum * 2) == 1)
    #expect(
        LibraryDeletionHoldPolicy.isArmed(
            downwardDragTranslation: LibraryDesignTokens.liftTrigger - 1,
            isBundled: false,
            allowsDestructiveActions: true
        ) == false
    )
    #expect(
        LibraryDeletionHoldPolicy.isArmed(
            downwardDragTranslation: LibraryDesignTokens.liftTrigger,
            isBundled: false,
            allowsDestructiveActions: true
        )
    )
    #expect(
        LibraryDeletionHoldPolicy.isArmed(
            downwardDragTranslation: LibraryDesignTokens.liftTrigger,
            isBundled: true,
            allowsDestructiveActions: true
        ) == false
    )
    #expect(
        LibraryDeletionHoldPolicy.isArmed(
            downwardDragTranslation: LibraryDesignTokens.liftTrigger,
            isBundled: false,
            allowsDestructiveActions: false
        ) == false
    )
}

@Test
func verticalIntentRejectsHorizontalAndDiagonalDrags() {
    #expect(
        LibraryVerticalDragIntentPolicy.isClearlyVertical(
            translation: CGSize(width: 0, height: 8)
        )
    )
    #expect(
        LibraryVerticalDragIntentPolicy.isClearlyVertical(
            translation: CGSize(width: 8, height: 8)
        ) == false
    )
    #expect(
        LibraryVerticalDragIntentPolicy.isClearlyVertical(
            translation: CGSize(width: 12, height: 8)
        ) == false
    )
}
