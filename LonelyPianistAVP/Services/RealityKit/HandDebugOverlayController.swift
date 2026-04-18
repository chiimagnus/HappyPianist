import RealityKit
import SwiftUI
import UIKit

@MainActor
final class HandDebugOverlayController {
    private let rootEntity = Entity()
    private var hasAttachedRoot = false
    private var markerByKey: [String: ModelEntity] = [:]

    func update(
        fingerTipPositions: [String: SIMD3<Float>],
        content: RealityViewContent
    ) {
        if hasAttachedRoot == false {
            content.add(rootEntity)
            hasAttachedRoot = true
        }

        let existingKeys = Set(markerByKey.keys)
        let incomingKeys = Set(fingerTipPositions.keys)

        for key in existingKeys.subtracting(incomingKeys) {
            markerByKey[key]?.removeFromParent()
            markerByKey[key] = nil
        }

        for (key, position) in fingerTipPositions {
            let marker = markerByKey[key] ?? {
                let model = ModelEntity(
                    mesh: .generateSphere(radius: 0.006),
                    materials: [UnlitMaterial(color: AVPOverlayPalette.handTipColor)]
                )
                rootEntity.addChild(model)
                markerByKey[key] = model
                return model
            }()
            marker.position = position
        }
    }
}
