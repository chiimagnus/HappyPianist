import RealityKit
import SwiftUI

@MainActor
final class PanoramaBackgroundController {
    private var backgroundEntity: ModelEntity?
    private var loadedBaseName: String?
    private var loadTask: Task<Void, Never>?

    func update(isEnabled: Bool, desiredBaseName: String?, content: RealityViewContent) {
        guard isEnabled else {
            tearDown(using: content)
            return
        }

        let entity = attachEntityIfNeeded(to: content)
        updateTextureIfNeeded(for: entity, desiredBaseName: desiredBaseName)
    }

    func shutdown() {
        loadTask?.cancel()
        loadTask = nil
        loadedBaseName = nil
        backgroundEntity?.removeFromParent()
        backgroundEntity = nil
    }

    private func attachEntityIfNeeded(to content: RealityViewContent) -> ModelEntity {
        if let backgroundEntity {
            return backgroundEntity
        }

        let sphereMesh = MeshResource.generateSphere(radius: 100.0)
        var material = UnlitMaterial(color: UIColor.white)
        material.faceCulling = .front

        let entity = ModelEntity(mesh: sphereMesh, materials: [material])
        entity.orientation = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        content.add(entity)

        backgroundEntity = entity
        return entity
    }

    private func tearDown(using content: RealityViewContent) {
        loadTask?.cancel()
        loadTask = nil
        loadedBaseName = nil

        guard let backgroundEntity else { return }
        content.remove(backgroundEntity)
        backgroundEntity.removeFromParent()
        self.backgroundEntity = nil
    }

    private func updateTextureIfNeeded(for entity: ModelEntity, desiredBaseName: String?) {
        guard loadedBaseName != desiredBaseName else { return }

        loadTask?.cancel()
        loadTask = nil
        loadedBaseName = desiredBaseName

        guard let desiredBaseName else {
            applyPlainMaterial(to: entity)
            return
        }

        guard let url = url(forPanoramaBaseName: desiredBaseName) else {
            applyPlainMaterial(to: entity)
            return
        }

        let requestedBaseName = desiredBaseName
        loadTask = Task { [weak entity] in
            let texture = try? await TextureResource(contentsOf: url)
            guard let texture else { return }
            guard Task.isCancelled == false else { return }

            var texturedMaterial = UnlitMaterial()
            texturedMaterial.color = .init(tint: UIColor.white, texture: .init(texture))
            texturedMaterial.faceCulling = .front

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.loadedBaseName == requestedBaseName else { return }
                entity?.model?.materials = [texturedMaterial]
                self.loadTask = nil
            }
        }
    }

    private func applyPlainMaterial(to entity: ModelEntity) {
        var material = UnlitMaterial(color: UIColor.white)
        material.faceCulling = .front
        entity.model?.materials = [material]
    }

    private func url(forPanoramaBaseName baseName: String) -> URL? {
        Bundle.main.url(forResource: baseName, withExtension: "jpg", subdirectory: "fullspace")
            ?? Bundle.main.url(forResource: baseName, withExtension: "jpg")
            ?? Bundle.main.url(forResource: baseName, withExtension: "jpeg", subdirectory: "fullspace")
            ?? Bundle.main.url(forResource: baseName, withExtension: "jpeg")
            ?? Bundle.main.url(forResource: baseName, withExtension: "png", subdirectory: "fullspace")
            ?? Bundle.main.url(forResource: baseName, withExtension: "png")
    }
}

