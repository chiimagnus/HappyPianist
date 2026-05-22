import ARKit
import Testing

@Test("ARKit required authorizations for current providers")
@MainActor
func arkitRequiredAuthorizationsForCurrentProviders() {
    // This test is intentionally simple: it gives us hard evidence about which
    // ARKitSession.AuthorizationType values our providers actually require on
    // the current SDK/runtime.

    let worldRequired = WorldTrackingProvider.requiredAuthorizations
    #expect(worldRequired.contains(.worldSensing) == false)

    // `cameraAccess` exists on newer visionOS versions. If ARKit ever starts
    // requiring it for world tracking, this expectation will fail and we'll
    // know `NSCameraUsageDescription` (or equivalent) is needed.
    if #available(visionOS 2.0, *) {
        #expect(worldRequired.contains(.cameraAccess) == false)
    }

    let handRequired = HandTrackingProvider.requiredAuthorizations
    #expect(handRequired.contains(.handTracking))
    if #available(visionOS 2.0, *) {
        #expect(handRequired.contains(.cameraAccess) == false)
    }
}
