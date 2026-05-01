import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
func virtualKeyboardPoseWithDeviceTransformProducesOrthonormalBasis() {
    let service = VirtualKeyboardPoseService()

    let planeWorldFromAnchor = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))

    let handCenterOnPlaneWorld = SIMD3<Float>(0, 0, -1)
    let deviceWorldTransform = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 1, 0, 1)
    ))

    let worldFromKeyboard = service.computeWorldFromKeyboard(
        planeWorldFromAnchor: planeWorldFromAnchor,
        handCenterOnPlaneWorld: handCenterOnPlaneWorld,
        deviceWorldTransform: deviceWorldTransform
    )

    #expect(worldFromKeyboard != nil)

    let x = SIMD3<Float>(worldFromKeyboard!.columns.0.x, worldFromKeyboard!.columns.0.y, worldFromKeyboard!.columns.0.z)
    let y = SIMD3<Float>(worldFromKeyboard!.columns.1.x, worldFromKeyboard!.columns.1.y, worldFromKeyboard!.columns.1.z)
    let z = SIMD3<Float>(worldFromKeyboard!.columns.2.x, worldFromKeyboard!.columns.2.y, worldFromKeyboard!.columns.2.z)

    #expect(abs(simd_dot(x, y)) < 1e-3)
    #expect(abs(simd_dot(y, z)) < 1e-3)
    #expect(abs(simd_dot(z, x)) < 1e-3)
    #expect(abs(simd_length(x) - 1) < 1e-3)
    #expect(abs(simd_length(y) - 1) < 1e-3)
    #expect(abs(simd_length(z) - 1) < 1e-3)
    #expect(simd_dot(y, SIMD3<Float>(0, 1, 0)) > 0.99)
}

@Test
func virtualKeyboardPoseWithoutDeviceTransformFallsBackToPlaneForward() {
    let service = VirtualKeyboardPoseService()

    // Plane forward is +X; after projection onto plane, should become +X.
    let planeWorldFromAnchor = simd_float4x4(columns: (
        SIMD4<Float>(0, 0, -1, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))

    let worldFromKeyboard = service.computeWorldFromKeyboard(
        planeWorldFromAnchor: planeWorldFromAnchor,
        handCenterOnPlaneWorld: SIMD3<Float>(0, 0, 0),
        deviceWorldTransform: nil
    )

    #expect(worldFromKeyboard != nil)

    let y = SIMD3<Float>(worldFromKeyboard!.columns.1.x, worldFromKeyboard!.columns.1.y, worldFromKeyboard!.columns.1.z)
    let z = SIMD3<Float>(worldFromKeyboard!.columns.2.x, worldFromKeyboard!.columns.2.y, worldFromKeyboard!.columns.2.z)

    #expect(simd_dot(y, SIMD3<Float>(0, 1, 0)) > 0.99)
    #expect(simd_dot(z, SIMD3<Float>(1, 0, 0)) > 0.99)
}

@Test
func virtualKeyboardPoseFlipsDownwardPlaneNormalToUpward() {
    let service = VirtualKeyboardPoseService()

    let planeWorldFromAnchor = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, -1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))

    let handCenterOnPlaneWorld = SIMD3<Float>(0, 0, -1)
    let deviceWorldTransform = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 1, 0, 1)
    ))

    let worldFromKeyboard = service.computeWorldFromKeyboard(
        planeWorldFromAnchor: planeWorldFromAnchor,
        handCenterOnPlaneWorld: handCenterOnPlaneWorld,
        deviceWorldTransform: deviceWorldTransform
    )

    #expect(worldFromKeyboard != nil)

    let y = SIMD3<Float>(worldFromKeyboard!.columns.1.x, worldFromKeyboard!.columns.1.y, worldFromKeyboard!.columns.1.z)
    #expect(simd_dot(y, SIMD3<Float>(0, 1, 0)) > 0.99)
}
