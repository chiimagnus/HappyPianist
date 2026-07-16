import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func virtualPerformerGaitResolverZeroSpeedIsNeutral() {
    let resolver = VirtualPerformerOverlayController.DefaultVirtualPerformerGaitResolver()
    let pose = resolver.gaitPose(phaseRadians: 1.23, lateralSpeedMetersPerSecond: 0)
    #expect(pose.leftAngleRadians == 0)
    #expect(pose.rightAngleRadians == 0)
}

@MainActor
@Test
func virtualPerformerGaitResolverProducesOppositeLegSwings() {
    let resolver = VirtualPerformerOverlayController.DefaultVirtualPerformerGaitResolver()
    let pose = resolver.gaitPose(phaseRadians: .pi / 2, lateralSpeedMetersPerSecond: 0.2)
    #expect(pose.leftAngleRadians > 0)
    #expect(pose.rightAngleRadians < 0)
    #expect(abs(pose.leftAngleRadians + pose.rightAngleRadians) < 0.0001)
}
