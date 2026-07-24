import RealityKit
import simd
import UIKit

@MainActor
final class PianoKeyEntityFactory {
    private struct MeshKey: Hashable {
        let x: UInt32
        let y: UInt32
        let z: UInt32

        init(size: SIMD3<Float>) {
            x = size.x.bitPattern
            y = size.y.bitPattern
            z = size.z.bitPattern
        }
    }

    private var meshBySize: [MeshKey: MeshResource] = [:]
    private lazy var whiteKeyMaterial: SimpleMaterial = makeMaterial(color: .white)
    private lazy var blackKeyMaterial: SimpleMaterial = makeMaterial(color: .black)

    func makeEntity(for key: PianoKeyGeometry) -> ModelEntity {
        let meshKey = MeshKey(size: key.localSize)
        let mesh: MeshResource
        if let cached = meshBySize[meshKey] {
            mesh = cached
        } else {
            let generated = MeshResource.generateBox(size: key.localSize)
            meshBySize[meshKey] = generated
            mesh = generated
        }

        let material = switch key.kind {
        case .white: whiteKeyMaterial
        case .black: blackKeyMaterial
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = key.localCenter
        return entity
    }

    private func makeMaterial(color: UIColor) -> SimpleMaterial {
        var material = SimpleMaterial(color: color, isMetallic: false)
        material.roughness = 0.5
        return material
    }
}
