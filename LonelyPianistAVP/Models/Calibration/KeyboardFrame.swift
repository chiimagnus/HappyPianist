import simd

/// A deterministic, horizontal keyboard coordinate frame derived from calibrated A0/C8 points.
///
/// Convention:
/// - Keyboard-local origin is A0 projected onto the horizontal plane at `planeHeight`.
/// - +X points from A0 towards C8, projected onto the XZ plane (y = 0).
/// - +Y is world up (0,1,0).
/// - +Z is derived deterministically to form a right-handed basis; it is a convention (not "towards the user").
struct KeyboardFrame {
    let worldFromKeyboard: simd_float4x4
    let keyboardFromWorld: simd_float4x4

    init?(a0World: SIMD3<Float>, c8World: SIMD3<Float>, planeHeight: Float) {
        let xCandidate = SIMD3<Float>(c8World.x - a0World.x, 0, c8World.z - a0World.z)
        let xLen = simd_length(xCandidate)
        if xLen < 1e-5 {
            return nil
        }

        let yAxis = SIMD3<Float>(0, 1, 0)

        // Build a right-handed, horizontal basis:
        // - x points A0 -> C8 (projected onto XZ)
        // - y is world up
        // - z is derived so that cross(x, y) == z
        // Then recompute x from (y,z) to guarantee orthonormality.
        let xAxisProjected = xCandidate / xLen
        let zAxis = simd_normalize(simd_cross(xAxisProjected, yAxis))
        let xAxis = simd_normalize(simd_cross(yAxis, zAxis))

        let origin = SIMD3<Float>(a0World.x, planeHeight, a0World.z)

        let wFromK = simd_float4x4(columns: (
            SIMD4<Float>(xAxis, 0),
            SIMD4<Float>(yAxis, 0),
            SIMD4<Float>(zAxis, 0),
            SIMD4<Float>(origin, 1)
        ))

        worldFromKeyboard = wFromK
        keyboardFromWorld = simd_inverse(wFromK)
    }
}

extension KeyboardFrame {
    var xAxisWorld: SIMD3<Float> {
        SIMD3<Float>(
            worldFromKeyboard.columns.0.x,
            worldFromKeyboard.columns.0.y,
            worldFromKeyboard.columns.0.z
        )
    }

    var yAxisWorld: SIMD3<Float> {
        SIMD3<Float>(
            worldFromKeyboard.columns.1.x,
            worldFromKeyboard.columns.1.y,
            worldFromKeyboard.columns.1.z
        )
    }

    var zAxisWorld: SIMD3<Float> {
        SIMD3<Float>(
            worldFromKeyboard.columns.2.x,
            worldFromKeyboard.columns.2.y,
            worldFromKeyboard.columns.2.z
        )
    }

    var originWorld: SIMD3<Float> {
        SIMD3<Float>(
            worldFromKeyboard.columns.3.x,
            worldFromKeyboard.columns.3.y,
            worldFromKeyboard.columns.3.z
        )
    }
}

extension PianoCalibration {
    var keyboardFrame: KeyboardFrame? {
        KeyboardFrame(a0World: a0.simdValue, c8World: c8.simdValue, planeHeight: planeHeight)
    }
}
