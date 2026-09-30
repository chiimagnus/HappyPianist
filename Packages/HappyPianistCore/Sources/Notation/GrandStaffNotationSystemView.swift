import Practice
import SwiftUI

struct GrandStaffNotationSystemView: View {
    let system: GrandStaffNotationPagePlan.System
    let plan: GrandStaffNotationPagePlan
    let staffSpace: Double
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let presentation = GrandStaffNotationPresentationViewModel().makePresentation(system: system, staffSpace: staffSpace, projection: plan.input.projection, overlay: overlay, practiceHandMode: practiceHandMode)
        let descriptor = GrandStaffNotationAccessibilityDescriptor.make(projection: plan.input.projection, layout: presentation.notationLayout, measureSpans: system.measures, currentTick: nil, activeTickRange: overlay.activeTickRange)
        Canvas { context, _ in
            GrandStaffNotationRenderer().draw(presentation: presentation, in: context, displayScale: displayScale, differentiateWithoutColor: differentiateWithoutColor)
        }
        .frame(width: presentation.canvasLayout.size.width, height: presentation.canvasLayout.size.height)
        .accessibilityRepresentation {
            VStack {
                ForEach(descriptor.elements) { element in Text(element.label) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(descriptor.containerLabel)
            .accessibilityValue(descriptor.containerValue)
        }
    }
}
