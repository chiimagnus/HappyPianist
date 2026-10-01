import simd

struct SpatialLibraryPlacementResolver {
    static let defaultDistanceMeters: Float = 1.1
    static let defaultVerticalOffsetMeters: Float = -0.05

    let distanceMeters: Float
    let verticalOffsetMeters: Float

    init(
        distanceMeters: Float = Self.defaultDistanceMeters,
        verticalOffsetMeters: Float = Self.defaultVerticalOffsetMeters
    ) {
        self.distanceMeters = distanceMeters
        self.verticalOffsetMeters = verticalOffsetMeters
    }

    func resolve(deviceWorldTransform: simd_float4x4) -> simd_float4x4? {
        let worldUp = SIMD3<Float>(0, 1, 0)
        let devicePosition = SIMD3<Float>(
            deviceWorldTransform.columns.3.x,
            deviceWorldTransform.columns.3.y,
            deviceWorldTransform.columns.3.z
        )
        guard Self.isFinite(devicePosition) else { return nil }

        let deviceZ = SIMD3<Float>(
            deviceWorldTransform.columns.2.x,
            deviceWorldTransform.columns.2.y,
            deviceWorldTransform.columns.2.z
        )
        var forward = SIMD3<Float>(-deviceZ.x, 0, -deviceZ.z)

        if simd_length_squared(forward) < 1e-6 {
            let deviceX = SIMD3<Float>(
                deviceWorldTransform.columns.0.x,
                0,
                deviceWorldTransform.columns.0.z
            )
            guard simd_length_squared(deviceX) >= 1e-6 else { return nil }
            forward = simd_cross(worldUp, simd_normalize(deviceX))
        }

        guard Self.isFinite(forward), simd_length_squared(forward) >= 1e-6 else { return nil }
        forward = simd_normalize(forward)

        let zAxis = -forward
        let xCandidate = simd_cross(worldUp, zAxis)
        guard simd_length_squared(xCandidate) >= 1e-6 else { return nil }

        let xAxis = simd_normalize(xCandidate)
        let zAxisOrthonormal = simd_normalize(simd_cross(xAxis, worldUp))
        let origin = devicePosition
            + forward * distanceMeters
            + worldUp * verticalOffsetMeters

        guard Self.isFinite(xAxis),
              Self.isFinite(zAxisOrthonormal),
              Self.isFinite(origin)
        else {
            return nil
        }

        return simd_float4x4(columns: (
            SIMD4<Float>(xAxis, 0),
            SIMD4<Float>(worldUp, 0),
            SIMD4<Float>(zAxisOrthonormal, 0),
            SIMD4<Float>(origin, 1)
        ))
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
