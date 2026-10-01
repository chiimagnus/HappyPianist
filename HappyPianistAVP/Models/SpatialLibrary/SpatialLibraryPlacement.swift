import simd

struct SpatialLibraryPlacement: Equatable {
    let worldFromSpatialLibrary: simd_float4x4
    let worldTrackingGeneration: Int
}

enum SpatialLibraryPlacementFailure: Equatable {
    case worldTrackingUnsupported
    case worldTrackingUnauthorized
    case worldTrackingFailed(reason: String)
    case timedOut
}
