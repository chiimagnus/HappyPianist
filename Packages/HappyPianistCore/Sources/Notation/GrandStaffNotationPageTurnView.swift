import Practice
import SwiftUI

struct GrandStaffNotationPageTurnView: View, Animatable {
    let plan: GrandStaffNotationPagePlan
    let transition: GrandStaffNotationPageTurnState.Transition
    let staffSpace: Double
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    let annotations: [GrandStaffNotationMeasureAnnotation]
    nonisolated var progress: Double
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let halfGutter = plan.geometry.gutter * staffSpace / 2
        let pageWidth = plan.geometry.width * staffSpace
        let forward = transition.isForward
        let turning = transition.source != transition.target && progress < 1
        let angle = turning ? (forward ? -180.0 : 180.0) * progress : 0
        ZStack(alignment: .leading) {
            HStack(spacing: halfGutter * 2) {
                page(turning ? transition.underneathLeft : transition.target * 2)
                page(turning ? transition.underneathRight : transition.target * 2 + 1)
            }
            if turning {
                HStack(spacing: 0) {
                    if progress < 0.5 {
                        if forward { Color.clear.frame(width: halfGutter) }
                        page(transition.frontPage)
                        if !forward { Color.clear.frame(width: halfGutter) }
                    } else {
                        if !forward { Color.clear.frame(width: halfGutter) }
                        page(transition.backPage)
                        if forward { Color.clear.frame(width: halfGutter) }
                    }
                }
                .frame(width: pageWidth + halfGutter)
                .rotation3DEffect(.degrees(progress < 0.5 ? 0 : (forward ? 180 : -180)), axis: (x: 0, y: 1, z: 0))
                .shadow(color: .black.opacity(0.2 * sin(.pi * progress)), radius: staffSpace, x: forward ? -staffSpace : staffSpace)
                #if os(visionOS)
                .perspectiveRotationEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: forward ? .leading : .trailing, perspective: 0.3)
                #else
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: forward ? .leading : .trailing, perspective: 0.3)
                #endif
                .offset(x: forward ? pageWidth + halfGutter : 0)
            }
        }
        .frame(width: plan.geometry.spreadWidth * staffSpace, height: plan.geometry.height * staffSpace)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func page(_ index: Int) -> some View {
        GrandStaffNotationPageView(plan: plan, index: index, staffSpace: staffSpace, overlay: overlay, practiceHandMode: practiceHandMode, annotations: annotations)
            .accessibilityHidden(true)
    }
}
