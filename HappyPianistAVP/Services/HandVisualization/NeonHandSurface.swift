import simd

struct NeonHandSurface {
    struct Geometry: Equatable {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
    }

    private static let ringSides = 4
    private static let fingerChains = TrackedHandJoint.fingerChains
    private static let palmContour = TrackedHandJoint.palmJoints
    private static let fingerBaseRadii: [Float] = [0.014, 0.012, 0.013, 0.012, 0.010]
    private static let palmHalfThickness: Float = 0.003

    private static let ringVertexCount = fingerChains.reduce(0) { partial, chain in
        partial + chain.count * ringSides
    }
    private static let palmVertexCount = (palmContour.count + 1) * 2
    static let vertexCount = ringVertexCount + palmVertexCount + fingerChains.count
    static let triangleIndices = makeTriangleIndices()

    // ponytail: a four-sided tube and fixed palm fan keep updates at 115 vertices per hand;
    // move this to a GPU mesh only if Vision Pro profiling shows a measurable render cost.
    static func geometry(for skeleton: TrackedHandSkeleton) -> Geometry? {
        guard skeleton.isRenderable,
              let wrist = skeleton[.wrist],
              let indexMetacarpal = skeleton[.indexFingerMetacarpal],
              let littleMetacarpal = skeleton[.littleFingerMetacarpal]
        else {
            return nil
        }

        let palmNormal = unit(
            simd_cross(indexMetacarpal - wrist, littleMetacarpal - wrist),
            fallback: SIMD3<Float>(0, 0, 1)
        )
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tipCenters: [(position: SIMD3<Float>, normal: SIMD3<Float>)] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        tipCenters.reserveCapacity(fingerChains.count)

        for (fingerIndex, chain) in fingerChains.enumerated() {
            let chainPositions = chain.compactMap { skeleton[$0] }
            guard chainPositions.count == chain.count else { return nil }

            let radius = fingerBaseRadii[fingerIndex]
            var terminalTangent = palmNormal
            for ringIndex in chainPositions.indices {
                let tangent = fingerTangent(
                    positions: chainPositions,
                    index: ringIndex,
                    fallback: palmNormal
                )
                terminalTangent = tangent
                let crossAxis = unit(
                    simd_cross(tangent, palmNormal),
                    fallback: simd_cross(tangent, SIMD3<Float>(0, 1, 0))
                )
                let upAxis = unit(simd_cross(crossAxis, tangent), fallback: palmNormal)
                let taper = 1 - Float(ringIndex) / Float(max(1, chainPositions.count - 1)) * 0.48

                for side in 0 ..< ringSides {
                    let angle = Float(side) * .pi * 2 / Float(ringSides)
                    let radial = crossAxis * cos(angle) + upAxis * sin(angle)
                    positions.append(chainPositions[ringIndex] + radial * radius * taper)
                    normals.append(radial)
                }
            }
            tipCenters.append((
                position: chainPositions.last! + terminalTangent * radius * 0.32,
                normal: terminalTangent
            ))
        }

        let palmPositions = palmContour.compactMap { skeleton[$0] }
        guard palmPositions.count == palmContour.count else { return nil }
        let palmCenter = palmPositions.reduce(SIMD3<Float>.zero, +) / Float(palmPositions.count)

        positions.append(palmCenter + palmNormal * palmHalfThickness)
        normals.append(palmNormal)
        for position in palmPositions {
            positions.append(position + palmNormal * palmHalfThickness)
            normals.append(palmNormal)
        }
        positions.append(palmCenter - palmNormal * palmHalfThickness)
        normals.append(-palmNormal)
        for position in palmPositions {
            positions.append(position - palmNormal * palmHalfThickness)
            normals.append(-palmNormal)
        }
        for tip in tipCenters {
            positions.append(tip.position)
            normals.append(tip.normal)
        }

        guard positions.count == vertexCount, normals.count == vertexCount else { return nil }
        return Geometry(positions: positions, normals: normals)
    }

    private static func makeTriangleIndices() -> [UInt32] {
        var indices: [UInt32] = []
        indices.reserveCapacity(456)

        for (fingerIndex, chain) in fingerChains.enumerated() {
            for ringIndex in 0 ..< (chain.count - 1) {
                for side in 0 ..< ringSides {
                    let nextSide = (side + 1) % ringSides
                    let a = ringVertexIndex(finger: fingerIndex, ring: ringIndex, side: side)
                    let b = ringVertexIndex(finger: fingerIndex, ring: ringIndex, side: nextSide)
                    let c = ringVertexIndex(finger: fingerIndex, ring: ringIndex + 1, side: side)
                    let d = ringVertexIndex(finger: fingerIndex, ring: ringIndex + 1, side: nextSide)
                    indices += [UInt32(a), UInt32(c), UInt32(b), UInt32(b), UInt32(c), UInt32(d)]
                }
            }

            let tipCenter = tipCenterIndex(finger: fingerIndex)
            let lastRing = chain.count - 1
            for side in 0 ..< ringSides {
                let nextSide = (side + 1) % ringSides
                indices += [
                    UInt32(ringVertexIndex(finger: fingerIndex, ring: lastRing, side: side)),
                    UInt32(tipCenter),
                    UInt32(ringVertexIndex(finger: fingerIndex, ring: lastRing, side: nextSide)),
                ]
            }
        }

        for point in palmContour.indices {
            let nextPoint = (point + 1) % palmContour.count
            let front = palmFrontContourIndex(point)
            let frontNext = palmFrontContourIndex(nextPoint)
            let back = palmBackContourIndex(point)
            let backNext = palmBackContourIndex(nextPoint)
            indices += [
                UInt32(palmFrontCenterIndex), UInt32(front), UInt32(frontNext),
                UInt32(palmBackCenterIndex), UInt32(backNext), UInt32(back),
                UInt32(front), UInt32(back), UInt32(frontNext),
                UInt32(frontNext), UInt32(back), UInt32(backNext),
            ]
        }

        return indices
    }

    private static func ringVertexIndex(finger: Int, ring: Int, side: Int) -> Int {
        let precedingRings = fingerChains.prefix(finger).reduce(0) { partial, chain in
            partial + chain.count
        }
        return (precedingRings + ring) * ringSides + side
    }

    private static let palmFrontCenterIndex = ringVertexCount

    private static func palmFrontContourIndex(_ point: Int) -> Int {
        palmFrontCenterIndex + 1 + point
    }

    private static let palmBackCenterIndex = palmFrontCenterIndex + palmContour.count + 1

    private static func palmBackContourIndex(_ point: Int) -> Int {
        palmBackCenterIndex + 1 + point
    }

    private static func tipCenterIndex(finger: Int) -> Int {
        ringVertexCount + palmVertexCount + finger
    }

    private static func fingerTangent(
        positions: [SIMD3<Float>],
        index: Int,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        if index == positions.startIndex {
            return unit(positions[1] - positions[0], fallback: fallback)
        }
        if index == positions.index(before: positions.endIndex) {
            return unit(positions[index] - positions[index - 1], fallback: fallback)
        }
        return unit(positions[index + 1] - positions[index - 1], fallback: fallback)
    }

    private static func unit(_ vector: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(vector)
        guard length > 0.0001 else { return fallback }
        return vector / length
    }
}
