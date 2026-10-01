import SwiftUI
import Testing
@testable import HappyPianistAVP

@Test
func bookFlowPresentationHasSymmetricClampedDepthAndCenterEmphasis() {
    let center = LibraryBookFlowPresentation(signedDistance: 0)
    let left = LibraryBookFlowPresentation(signedDistance: -1)
    let right = LibraryBookFlowPresentation(signedDistance: 1)
    let far = LibraryBookFlowPresentation(signedDistance: 2)
    let beyond = LibraryBookFlowPresentation(signedDistance: 10)
    #expect(center.yawDegrees == 0)
    #expect(center.scale == 1 && center.opacity == 1)
    #expect(left.yawDegrees == -right.yawDegrees)
    #expect(abs(right.yawDegrees) == 58)
    #expect(left.lateralOffsetUnits == -right.lateralOffsetUnits)
    #expect(left.scale == right.scale && left.opacity == right.opacity)
    #expect(center.scale > right.scale && right.scale > far.scale)
    #expect(center.opacity > right.opacity && right.opacity > far.opacity)
    #expect(center.depthOffsetUnits > right.depthOffsetUnits && right.depthOffsetUnits > far.depthOffsetUnits)
    #expect(far == beyond)
}
