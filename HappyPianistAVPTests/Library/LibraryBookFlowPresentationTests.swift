import SwiftUI
import Testing
@testable import HappyPianistAVP

@Test
func bookFlowPresentationHasSymmetricClampedDepthAndCenterEmphasis() {
    let center = LibraryBookFlowPresentation(centerDistance: 0, itemExtent: 200, reduceMotion: false)
    let left = LibraryBookFlowPresentation(centerDistance: -200, itemExtent: 200, reduceMotion: false)
    let right = LibraryBookFlowPresentation(centerDistance: 200, itemExtent: 200, reduceMotion: false)
    let far = LibraryBookFlowPresentation(centerDistance: 400, itemExtent: 200, reduceMotion: false)
    let beyond = LibraryBookFlowPresentation(centerDistance: 2000, itemExtent: 200, reduceMotion: false)
    #expect(center.rotationDegrees == 0)
    #expect(center.scale == 1 && center.opacity == 1)
    #expect(left.rotationDegrees == -right.rotationDegrees)
    #expect(abs(right.rotationDegrees) == 58)
    #expect(left.horizontalOffset == -right.horizontalOffset)
    #expect(left.scale == right.scale && left.opacity == right.opacity)
    #expect(center.scale > right.scale && right.scale > far.scale)
    #expect(center.opacity > right.opacity && right.opacity > far.opacity)
    #expect(center.depthPriority > right.depthPriority && right.depthPriority > far.depthPriority)
    #expect(far == beyond)
}

@Test
func bookFlowReduceMotionKeepsEmphasisWithoutRotationOrDisplacement() {
    let center = LibraryBookFlowPresentation(centerDistance: 0, itemExtent: 200, reduceMotion: true)
    let neighbor = LibraryBookFlowPresentation(centerDistance: -200, itemExtent: 200, reduceMotion: true)
    #expect(neighbor.rotationDegrees == 0 && neighbor.horizontalOffset == 0)
    #expect(center.scale > neighbor.scale)
    #expect(center.depthPriority > neighbor.depthPriority)
}
