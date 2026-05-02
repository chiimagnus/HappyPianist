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

private struct ImmersiveNotationPanelView: View {
    @Bindable var sessionViewModel: PracticeSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("滚动五线谱")
                    .font(.headline)
                Spacer()
                if let currentGuide = sessionViewModel.currentPianoHighlightGuide {
                    Text("tick \(currentGuide.tick)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ScrollingStaffNotationView(
                guides: sessionViewModel.highlightGuides,
                currentGuide: sessionViewModel.currentPianoHighlightGuide,
                measureSpans: sessionViewModel.notationMeasureSpans,
                context: sessionViewModel.currentNotationContext
            )
            .frame(width: 760, height: 190)
        }
        .padding(18)
        .frame(width: 820)
        .glassBackgroundEffect()
    }
}
