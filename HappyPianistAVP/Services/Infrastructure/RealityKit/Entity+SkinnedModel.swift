import RealityKit

extension Entity {
    @MainActor
    func firstSkinnedModelEntity() -> ModelEntity? {
        if let modelEntity = self as? ModelEntity, modelEntity.jointNames.isEmpty == false {
            return modelEntity
        }

        for child in children {
            if let modelEntity = child.firstSkinnedModelEntity() {
                return modelEntity
            }
        }
        return nil
    }
}
