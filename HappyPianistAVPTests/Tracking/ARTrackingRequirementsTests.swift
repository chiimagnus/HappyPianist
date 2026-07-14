@testable import HappyPianistAVP
import Testing

@Test
func trackingRequirementsOnlyEnablePlaneDetectionDuringVirtualPianoPlacement() {
    let base: ARTrackingRequirements = [.hand, .world]

    #expect(ARTrackingRequirements.calibration == base)
    #expect(ARTrackingRequirements.practice(
        base: base,
        requiresHorizontalPlanePlacement: false
    ) == base)
    #expect(ARTrackingRequirements.practice(
        base: base,
        requiresHorizontalPlanePlacement: true
    ) == [.hand, .world, .horizontalPlanes])
}

@Test
func bluetoothMidiModeDoesNotRequestHandOrPlaneTracking() throws {
    let mode = try #require(
        PianoModeCatalogService.makeDefaultModes().first(where: { $0.id == PianoModeID.bluetoothMIDI.rawValue })
    )

    #expect(mode.practiceTrackingRequirements == [.world])
}
