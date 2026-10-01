import Practice
import SwiftUI

struct GrandStaffNotationSystemView: View {
    let system: GrandStaffNotationPagePlan.System
    let plan: GrandStaffNotationPagePlan
    let staffSpace: Double
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let presentation = GrandStaffNotationPresentationViewModel().makePresentation(system: system, staffSpace: staffSpace, projection: plan.input.projection, overlay: overlay, practiceHandMode: practiceHandMode)
        Canvas { context, _ in
            GrandStaffNotationRenderer().draw(presentation: presentation, in: context, displayScale: displayScale)
        }
        .frame(width: presentation.canvasLayout.size.width, height: presentation.canvasLayout.size.height)
    }
}
