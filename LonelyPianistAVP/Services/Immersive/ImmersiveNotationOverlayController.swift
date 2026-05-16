import RealityKit
import SwiftUI

@MainActor
final class ImmersiveNotationOverlayController {
    private var panelEntity = Entity()
    private var hasAttachedPanel = false

    func update(sessionViewModel: PracticeSessionViewModel, content: RealityViewContent) {
        if hasAttachedPanel == false {
            panelEntity.components.set(ViewAttachmentComponent(
                rootView: ImmersiveNotationPanelView(sessionViewModel: sessionViewModel)
            ))
            panelEntity.position = SIMD3<Float>(0, 1.18, -1.05)
            panelEntity.scale = SIMD3<Float>(1.0, 1.0, 1.0)
            content.add(panelEntity)
            hasAttachedPanel = true
        }

        panelEntity.isEnabled = sessionViewModel.highlightGuides.isEmpty == false
    }
}
