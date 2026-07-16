@testable import HappyPianistAVP
import CoreGraphics
import Testing

@Test
func carouselPoseUsesFiveLayeredPositions() {
    let expectations: [(
        position: CGFloat,
        horizontalOffset: CGFloat,
        scale: CGFloat,
        opacity: Double,
        saturation: Double,
        horizontalScale: CGFloat
    )] = [
        (-2, -LibraryDesignTokens.carouselOuterOffset, 0.66, 0.42, 0.70, 0.86),
        (-1, -LibraryDesignTokens.carouselNeighborOffset, 0.82, 0.82, 0.88, 0.92),
        (0, 0, 1, 1, 1, 1),
        (1, LibraryDesignTokens.carouselNeighborOffset, 0.82, 0.82, 0.88, 0.92),
        (2, LibraryDesignTokens.carouselOuterOffset, 0.66, 0.42, 0.70, 0.86),
    ]

    for expectation in expectations {
        let pose = LibraryCarouselPose(relativePosition: expectation.position)
        #expect(pose.horizontalOffset == expectation.horizontalOffset)
        #expect(pose.scale == expectation.scale)
        #expect(pose.opacity == expectation.opacity)
        #expect(pose.saturation == expectation.saturation)
        #expect(pose.horizontalScale == expectation.horizontalScale)
    }
}

@Test
func carouselPoseInterpolatesDuringDragAndClampsHiddenRecords() {
    let midway = LibraryCarouselPose(relativePosition: 0.5)
    let hidden = LibraryCarouselPose(relativePosition: 5)

    #expect(midway.horizontalOffset == LibraryDesignTokens.carouselNeighborOffset / 2)
    #expect(midway.scale == 0.91)
    #expect(midway.opacity == 0.91)
    #expect(midway.horizontalScale == 0.96)
    #expect(hidden.horizontalOffset == LibraryDesignTokens.carouselHiddenOffset)
    #expect(hidden.opacity == 0)
    #expect(hidden.zIndex == 0)
}

@Test
func carouselSelectionDirectionHonorsTheReleaseThreshold() {
    #expect(LibraryCarouselSelectionDirection.from(horizontalDragTranslation: -59) == nil)
    #expect(LibraryCarouselSelectionDirection.from(horizontalDragTranslation: 59) == nil)
    #expect(LibraryCarouselSelectionDirection.from(horizontalDragTranslation: -60) == .next)
    #expect(LibraryCarouselSelectionDirection.from(horizontalDragTranslation: 60) == .previous)
}

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
