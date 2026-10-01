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
        let height = plan.geometry.height * staffSpace
        let curl = GrandStaffNotationPageCurlGeometry(width: pageWidth, height: height, gutter: halfGutter * 2, progress: progress, forward: forward)
        ZStack(alignment: .leading) {
            HStack(spacing: halfGutter * 2) {
                page(turning ? transition.underneathLeft : transition.target * 2)
                page(turning ? transition.underneathRight : transition.target * 2 + 1)
            }
            if turning {
                surface(curl: curl)
            }
        }
        .frame(width: plan.geometry.spreadWidth * staffSpace, height: plan.geometry.height * staffSpace)
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
    }

    private func surface(curl: GrandStaffNotationPageCurlGeometry) -> some View {
        let horizontalPadding = curl.sheetWidth * (curl.maximumScale - 1) + staffSpace
        let verticalPadding = curl.height / 2 * (curl.maximumScale - 1) + staffSpace
        return HStack(spacing: curl.gutter) {
            page(curl.forward ? transition.backPage : transition.frontPage)
            page(curl.forward ? transition.frontPage : transition.backPage)
        }
        .frame(width: curl.spreadWidth, height: curl.height)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .compositingGroup()
        .layerEffect(ShaderLibrary.bundle(.module).scorePageCurl(
            .float2(curl.spreadWidth, curl.height), .float2(horizontalPadding, verticalPadding),
            .float(curl.gutter), .float(curl.rotation), .float(curl.curvature),
            .float(curl.cameraDistance), .float(curl.direction)),
            maxSampleOffset: curl.maximumSampleOffset)
        .shadow(color: .black.opacity(0.18 * sin(.pi * progress)), radius: staffSpace,
                x: curl.direction * staffSpace, y: staffSpace * 0.5)
        .padding(.horizontal, -horizontalPadding)
        .padding(.vertical, -verticalPadding)
    }

    private func page(_ index: Int) -> some View {
        GrandStaffNotationPageView(plan: plan, index: index, staffSpace: staffSpace, overlay: overlay, practiceHandMode: practiceHandMode, annotations: annotations)
    }
}
