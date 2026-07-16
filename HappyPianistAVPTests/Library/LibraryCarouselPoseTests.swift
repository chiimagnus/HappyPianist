@testable import HappyPianistAVP
import CoreGraphics
import SwiftUI
import Testing

@Test
func carouselPoseUsesFiveLayeredPositions() {
    let expectations: [(
        position: CGFloat,
        horizontalOffset: CGFloat,
        scale: CGFloat,
        opacity: Double,
        saturation: Double,
        rotationY: Double
    )] = [
        (-2, -LibraryDesignTokens.carouselOuterOffset, 0.66, 0.42, 0.70, 14),
        (-1, -LibraryDesignTokens.carouselNeighborOffset, 0.82, 0.82, 0.88, 7),
        (0, 0, 1, 1, 1, 0),
        (1, LibraryDesignTokens.carouselNeighborOffset, 0.82, 0.82, 0.88, -7),
        (2, LibraryDesignTokens.carouselOuterOffset, 0.66, 0.42, 0.70, -14),
    ]

    for expectation in expectations {
        let pose = LibraryCarouselPose(relativePosition: expectation.position)
        #expect(pose.horizontalOffset == expectation.horizontalOffset)
        #expect(pose.scale == expectation.scale)
        #expect(pose.opacity == expectation.opacity)
        #expect(pose.saturation == expectation.saturation)
        #expect(pose.rotationY == expectation.rotationY)
    }
}

@Test
func carouselPoseInterpolatesDuringDragAndClampsHiddenRecords() {
    let midway = LibraryCarouselPose(relativePosition: 0.5)
    let hidden = LibraryCarouselPose(relativePosition: 5)

    #expect(midway.horizontalOffset == LibraryDesignTokens.carouselNeighborOffset / 2)
    #expect(midway.scale == 0.91)
    #expect(midway.opacity == 0.91)
    #expect(midway.rotationY == -3.5)
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
func carouselSelectionDirectionMapsTrackInfoToOpposingEdges() {
    #expect(LibraryCarouselSelectionDirection.next.trackInfoInsertionEdge == .trailing)
    #expect(LibraryCarouselSelectionDirection.next.trackInfoRemovalEdge == .leading)
    #expect(LibraryCarouselSelectionDirection.previous.trackInfoInsertionEdge == .leading)
    #expect(LibraryCarouselSelectionDirection.previous.trackInfoRemovalEdge == .trailing)
}
