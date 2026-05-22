@testable import LonelyPianistAVP
import simd
import Testing

@Test
func keyboardFrameProducesOrthonormalBasisAndCorrectInverse() throws {
    let a0 = SIMD3<Float>(0.0, 0.71, 0.0)
    let c8 = SIMD3<Float>(1.23, 0.69, -0.40) // includes some y noise that should be ignored for yaw
    let planeHeight: Float = 0.70

    let frame = try #require(KeyboardFrame(a0World: a0, c8World: c8, planeHeight: planeHeight))

    #expect(abs(simd_length(frame.xAxisWorld) - 1) < 1e-4)
    #expect(abs(simd_length(frame.yAxisWorld) - 1) < 1e-4)
    #expect(abs(simd_length(frame.zAxisWorld) - 1) < 1e-4)

    #expect(abs(simd_dot(frame.xAxisWorld, frame.yAxisWorld)) < 1e-4)
    #expect(abs(simd_dot(frame.yAxisWorld, frame.zAxisWorld)) < 1e-4)
    #expect(abs(simd_dot(frame.xAxisWorld, frame.zAxisWorld)) < 1e-4)

    // Right-handed: cross(x, y) == z
    let crossXY = simd_cross(frame.xAxisWorld, frame.yAxisWorld)
    #expect(simd_length(crossXY - frame.zAxisWorld) < 1e-4)

    #expect(abs(frame.originWorld.y - planeHeight) < 1e-6)

    let identity = simd_mul(frame.keyboardFromWorld, frame.worldFromKeyboard)
    #expect(abs(identity.columns.0.x - 1) < 1e-4)
    #expect(abs(identity.columns.1.y - 1) < 1e-4)
    #expect(abs(identity.columns.2.z - 1) < 1e-4)
    #expect(abs(identity.columns.3.w - 1) < 1e-4)

    #expect(abs(identity.columns.0.y) < 1e-4)
    #expect(abs(identity.columns.0.z) < 1e-4)
    #expect(abs(identity.columns.1.x) < 1e-4)
    #expect(abs(identity.columns.1.z) < 1e-4)
    #expect(abs(identity.columns.2.x) < 1e-4)
    #expect(abs(identity.columns.2.y) < 1e-4)
    #expect(abs(identity.columns.3.x) < 1e-4)
    #expect(abs(identity.columns.3.y) < 1e-4)
    #expect(abs(identity.columns.3.z) < 1e-4)
}

@Test
func keyboardFrameReturnsNilForDegenerateHorizontalVector() {
    let a0 = SIMD3<Float>(0.1, 0.7, -0.2)
    let c8 = SIMD3<Float>(0.1, 0.9, -0.2) // same x/z, only y differs
    let frame = KeyboardFrame(a0World: a0, c8World: c8, planeHeight: 0.7)
    #expect(frame == nil)
}
