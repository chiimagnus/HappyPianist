import RealityKit
import simd

enum PianoGuideDecalMeshFactory {
    static let unitTopDecalMesh: MeshResource = {
        var descriptor = MeshDescriptor()

        let half: Float = 0.5

        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-half, 0, half),
            SIMD3<Float>(half, 0, half),
            SIMD3<Float>(half, 0, -half),
            SIMD3<Float>(-half, 0, -half),
        ]

        let normal = SIMD3<Float>(0, 1, 0)
        let normals: [SIMD3<Float>] = [normal, normal, normal, normal]

        let uvs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 1),
        ]

        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]

        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return try! MeshResource.generate(from: [descriptor])
    }()
}

