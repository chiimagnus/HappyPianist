import simd

struct GazeRay: Equatable {
    let originWorld: SIMD3<Float>
    let directionWorld: SIMD3<Float>

    var normalizedDirectionWorld: SIMD3<Float>? {
        let len = simd_length(directionWorld)
        guard len > 1e-6 else { return nil }
        return directionWorld / len
    }
}

