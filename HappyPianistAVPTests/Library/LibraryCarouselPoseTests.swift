@testable import HappyPianistAVP
import CoreGraphics
import Testing

@Test
func carouselPoseUsesFiveLayeredPositions() {
    let center = LibraryCarouselPose(relativePosition: 0)
    let neighbor = LibraryCarouselPose(relativePosition: 1)
    let outer = LibraryCarouselPose(relativePosition: -2)

    #expect(center.horizontalOffset == 0)
    #expect(center.scale == 1)
    #expect(center.opacity == 1)
    #expect(center.rotationY == 0)
    #expect(neighbor.horizontalOffset == LibraryDesignTokens.carouselNeighborOffset)
    #expect(neighbor.scale == 0.82)
    #expect(neighbor.opacity == 0.82)
    #expect(neighbor.rotationY == -7)
    #expect(outer.horizontalOffset == -LibraryDesignTokens.carouselOuterOffset)
    #expect(outer.scale == 0.66)
    #expect(outer.opacity == 0.42)
    #expect(outer.rotationY == 14)
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
