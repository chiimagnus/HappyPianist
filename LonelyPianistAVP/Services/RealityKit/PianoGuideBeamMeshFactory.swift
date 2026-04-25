import RealityKit
import simd

enum PianoGuideBeamMeshFactory {
    static let unitPrismShellMesh: MeshResource = {
        var descriptor = MeshDescriptor()

        let half: Float = 0.5

        let u0: Float = 0.0
        let u1: Float = 0.25
        let u2: Float = 0.50
        let u3: Float = 0.75
        let u4: Float = 1.0
        let v0: Float = 0.0
        let v1: Float = 1.0

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        func appendQuad(
            p0: SIMD3<Float>,
            p1: SIMD3<Float>,
            p2: SIMD3<Float>,
            p3: SIMD3<Float>,
            normal: SIMD3<Float>,
            uv0: SIMD2<Float>,
            uv1: SIMD2<Float>,
            uv2: SIMD2<Float>,
            uv3: SIMD2<Float>
        ) {
            let baseIndex = UInt32(positions.count)
            positions.append(contentsOf: [p0, p1, p2, p3])
            normals.append(contentsOf: [normal, normal, normal, normal])
            uvs.append(contentsOf: [uv0, uv1, uv2, uv3])
            indices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex, baseIndex + 2, baseIndex + 3
            ])
        }

        // Front (+Z) -> atlas [0.00, 0.25]
        appendQuad(
            p0: SIMD3<Float>(-half, -half, half),
            p1: SIMD3<Float>(half, -half, half),
            p2: SIMD3<Float>(half, half, half),
            p3: SIMD3<Float>(-half, half, half),
            normal: SIMD3<Float>(0, 0, 1),
            uv0: SIMD2<Float>(u0, v0),
            uv1: SIMD2<Float>(u1, v0),
            uv2: SIMD2<Float>(u1, v1),
            uv3: SIMD2<Float>(u0, v1)
        )

        // Right (+X) -> atlas [0.25, 0.50]
        appendQuad(
            p0: SIMD3<Float>(half, -half, half),
            p1: SIMD3<Float>(half, -half, -half),
            p2: SIMD3<Float>(half, half, -half),
            p3: SIMD3<Float>(half, half, half),
            normal: SIMD3<Float>(1, 0, 0),
            uv0: SIMD2<Float>(u1, v0),
            uv1: SIMD2<Float>(u2, v0),
            uv2: SIMD2<Float>(u2, v1),
            uv3: SIMD2<Float>(u1, v1)
        )

        // Back (-Z) -> atlas [0.50, 0.75]
        appendQuad(
            p0: SIMD3<Float>(half, -half, -half),
            p1: SIMD3<Float>(-half, -half, -half),
            p2: SIMD3<Float>(-half, half, -half),
            p3: SIMD3<Float>(half, half, -half),
            normal: SIMD3<Float>(0, 0, -1),
            uv0: SIMD2<Float>(u2, v0),
            uv1: SIMD2<Float>(u3, v0),
            uv2: SIMD2<Float>(u3, v1),
            uv3: SIMD2<Float>(u2, v1)
        )

        // Left (-X) -> atlas [0.75, 1.00]
        appendQuad(
            p0: SIMD3<Float>(-half, -half, -half),
            p1: SIMD3<Float>(-half, -half, half),
            p2: SIMD3<Float>(-half, half, half),
            p3: SIMD3<Float>(-half, half, -half),
            normal: SIMD3<Float>(-1, 0, 0),
            uv0: SIMD2<Float>(u3, v0),
            uv1: SIMD2<Float>(u4, v0),
            uv2: SIMD2<Float>(u4, v1),
            uv3: SIMD2<Float>(u3, v1)
        )

        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            return .generateBox(size: SIMD3<Float>(repeating: 1))
        }
    }()
}

