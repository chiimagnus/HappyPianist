import Foundation
import simd

struct DetectedPlane: Identifiable, Equatable {
    let id: UUID
    let worldFromPlane: simd_float4x4

    var originWorld: SIMD3<Float> {
        SIMD3<Float>(worldFromPlane.columns.3.x, worldFromPlane.columns.3.y, worldFromPlane.columns.3.z)
    }

    /// Convention: `worldFromPlane.columns.1` is the plane normal (Y axis).
    var normalWorld: SIMD3<Float> {
        simd_normalize(SIMD3<Float>(worldFromPlane.columns.1.x, worldFromPlane.columns.1.y, worldFromPlane.columns.1.z))
    }

    /// Prefer an upward-pointing normal for consistency.
    var upwardNormalWorld: SIMD3<Float> {
        let up = SIMD3<Float>(0, 1, 0)
        let n = normalWorld
        return simd_dot(n, up) >= 0 ? n : -n
    }
}

struct PlaneHit: Equatable {
    let id: UUID
    let hitPointWorld: SIMD3<Float>
    let planeNormalWorld: SIMD3<Float>
    let distanceMeters: Float
}

